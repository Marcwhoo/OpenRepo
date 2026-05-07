# Client-Script zum Entfernen von Druckern ohne Gruppenmitgliedschaft
# Dieses Script sollte per GPO als Startup/Logon Script verteilt werden
# Performance-optimiert für 2000+ Benutzer (ohne Logging, ohne Server-Abfragen)
# Entfernt automatisch Drucker, wenn Benutzer nicht mehr in Sicherheitsgruppe ist
# OPTIMIERT: Keine Server-Abfragen mehr - nur lokale Prüfung + AD-Gruppenprüfung

param(
    [Parameter(Mandatory=$false)]
    [string]$PrintServer = "<PRINT-SERVER-1>-01",
    [Parameter(Mandatory=$false)]
    [string]$GroupOU = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Hole alle Gruppen aus der Drucker-OU und prüfe, ob Benutzer Mitglied ist
# OPTIMIERT: Nur 2 AD-Abfragen (Gruppen + Benutzer) - keine Server-Abfragen
try {
    $printerGroups = Get-ADGroup -Filter * -SearchBase $GroupOU -ErrorAction Stop
    $user = Get-ADUser -Identity $env:USERNAME -Properties MemberOf -ErrorAction Stop
    $userMemberOf = $user.MemberOf
    
    # Erstelle Hash-Table mit Gruppennamen, bei denen der Benutzer Mitglied ist
    $userGroupNames = @{}
    foreach ($group in $printerGroups) {
        if ($userMemberOf -contains $group.DistinguishedName) {
            $userGroupNames[$group.Name] = $true
        }
    }
} catch {
    exit 0
}

# Hole alle lokalen Drucker (nur lokal - keine Server-Abfrage!)
# Filtere Drucker vom neuen Server basierend auf PortName, ComputerName, SharePath
try {
    $allLocalPrinters = Get-Printer -ErrorAction Stop | Where-Object { 
        $_.Name -notlike "Microsoft*" -and 
        $_.Name -notlike "Fax*" -and
        $_.Name -notlike "OneNote*" -and
        $_.Name -notlike "Send To*"
    }
    
    $localPrinters = $allLocalPrinters | Where-Object {
        $printer = $_
        $printer.PortName -like "\\$PrintServer\*" -or
        $printer.ComputerName -like "*$PrintServer*" -or
        ($printer.SharePath -and $printer.SharePath -like "*\\$PrintServer\*") -or
        $printer.Name -like "\\$PrintServer\*" -or
        $printer.Name -like "* an $PrintServer" -or
        $printer.Name -like "*@$PrintServer*"
    }
} catch {
    exit 0
}

# Prüfe jeden lokalen Drucker
foreach ($localPrinter in $localPrinters) {
    $printerName = $localPrinter.Name
    
    # Extrahiere Druckernamen (entferne Server-Präfix falls vorhanden)
    $cleanName = $printerName -replace [regex]::Escape("\\$PrintServer\"), ""
    $cleanName = $cleanName.TrimStart('\')
    
    # Prüfe Gruppenmitgliedschaft basierend auf Druckernamen
    # Die Sicherheitsgruppen haben den gleichen Namen wie die Drucker
    # Prüfe sowohl den vollständigen Namen als auch den bereinigten Namen
    $shouldKeep = $false
    
    # Prüfe ob Benutzer in Gruppe mit Druckernamen ist
    if ($userGroupNames.ContainsKey($printerName)) {
        $shouldKeep = $true
    } elseif ($userGroupNames.ContainsKey($cleanName)) {
        $shouldKeep = $true
    } else {
        # Prüfe auch ShareName-Variante (kann Punkte durch Unterstriche ersetzen)
        $shareNameVariant = $cleanName -replace '\.', '_'
        if ($userGroupNames.ContainsKey($shareNameVariant)) {
            $shouldKeep = $true
        }
    }
    
    # Wenn Benutzer nicht in Gruppe ist, entfernen
    if (-not $shouldKeep) {
        if (-not $WhatIf) {
            try {
                Remove-Printer -Name $printerName -ErrorAction SilentlyContinue
            } catch {
                try {
                    Remove-Printer -Name $printerName -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        }
    }
}

exit 0
