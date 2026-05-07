# DEBUG-Version: Client-Script zum Entfernen von Druckern
# Diese Version hat Logging zum Debuggen
# OPTIMIERT: Keine Server-Abfragen mehr - nur lokale Prüfung + AD-Gruppenprüfung

param(
    [Parameter(Mandatory=$false)]
    [string]$PrintServer = "<PRINT-SERVER-1>-01",
    [Parameter(Mandatory=$false)]
    [string]$GroupOU = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$logFile = "$env:TEMP\PrinterCleanup-Debug.log"

function Write-DebugLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
}

Write-DebugLog "=== Starte Drucker-Bereinigung (OPTIMIERT - keine Server-Abfragen) ==="
Write-DebugLog "Benutzer: $env:USERNAME"
Write-DebugLog "Druckerserver: $PrintServer"
Write-DebugLog "Gruppen-OU: $GroupOU"

# Hole alle Gruppen aus der Drucker-OU und prüfe, ob Benutzer Mitglied ist
# OPTIMIERT: Nur 2 AD-Abfragen (Gruppen + Benutzer) - keine Server-Abfragen
try {
    $printerGroups = Get-ADGroup -Filter * -SearchBase $GroupOU -ErrorAction Stop
    Write-DebugLog "Gefunden: $($printerGroups.Count) Gruppen in Drucker-OU"
    
    $user = Get-ADUser -Identity $env:USERNAME -Properties MemberOf -ErrorAction Stop
    $userMemberOf = $user.MemberOf
    Write-DebugLog "Benutzer ist in $($userMemberOf.Count) Gruppen insgesamt"
    
    # Erstelle Hash-Table mit Gruppennamen, bei denen der Benutzer Mitglied ist
    $userGroupNames = @{}
    foreach ($group in $printerGroups) {
        if ($userMemberOf -contains $group.DistinguishedName) {
            $userGroupNames[$group.Name] = $true
            Write-DebugLog "  -> Benutzer ist Mitglied: $($group.Name)"
        }
    }
    
    Write-DebugLog "Benutzer ist in $($userGroupNames.Count) Gruppen aus Drucker-OU"
    Write-DebugLog "Gruppennamen: $($userGroupNames.Keys -join ', ')"
} catch {
    Write-DebugLog "FEHLER: AD nicht verfügbar: $($_.Exception.Message)"
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
    Write-DebugLog "Gefunden: $($allLocalPrinters.Count) lokale Drucker insgesamt"
    
    $localPrinters = $allLocalPrinters | Where-Object {
        $printer = $_
        $isFromServer = $false
        
        if ($printer.PortName -like "\\$PrintServer\*") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über PortName"
        } elseif ($printer.ComputerName -like "*$PrintServer*") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über ComputerName"
        } elseif ($printer.SharePath -and $printer.SharePath -like "*\\$PrintServer\*") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über SharePath: $($printer.SharePath)"
        } elseif ($printer.Name -like "\\$PrintServer\*") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über Name (UNC)"
        } elseif ($printer.Name -like "* an $PrintServer") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über Name (an Server)"
        } elseif ($printer.Name -like "*@$PrintServer*") {
            $isFromServer = $true
            Write-DebugLog "  Drucker $($printer.Name): Gefunden über Name (@Server)"
        }
        
        $isFromServer
    }
    Write-DebugLog "Gefunden: $($localPrinters.Count) lokale Drucker vom Server $PrintServer"
} catch {
    Write-DebugLog "FEHLER: Konnte lokale Drucker nicht abrufen: $($_.Exception.Message)"
    exit 0
}

# Prüfe jeden lokalen Drucker
foreach ($localPrinter in $localPrinters) {
    $printerName = $localPrinter.Name
    
    Write-DebugLog "Prüfe Drucker: $printerName"
    
    # Extrahiere Druckernamen (entferne Server-Präfix falls vorhanden)
    $cleanName = $printerName -replace [regex]::Escape("\\$PrintServer\"), ""
    $cleanName = $cleanName.TrimStart('\')
    Write-DebugLog "  -> Bereinigter Name: $cleanName"
    
    # Prüfe Gruppenmitgliedschaft basierend auf Druckernamen
    $shouldKeep = $false
    
    # Prüfe ob Benutzer in Gruppe mit Druckernamen ist
    if ($userGroupNames.ContainsKey($printerName)) {
        $shouldKeep = $true
        Write-DebugLog "  -> Benutzer ist in Gruppe (vollständiger Name): $printerName - BEHALTEN"
    } elseif ($userGroupNames.ContainsKey($cleanName)) {
        $shouldKeep = $true
        Write-DebugLog "  -> Benutzer ist in Gruppe (bereinigter Name): $cleanName - BEHALTEN"
    } else {
        # Prüfe auch ShareName-Variante (kann Punkte durch Unterstriche ersetzen)
        $shareNameVariant = $cleanName -replace '\.', '_'
        if ($userGroupNames.ContainsKey($shareNameVariant)) {
            $shouldKeep = $true
            Write-DebugLog "  -> Benutzer ist in Gruppe (ShareName-Variante): $shareNameVariant - BEHALTEN"
        } else {
            Write-DebugLog "  -> Benutzer ist NICHT in Gruppe - ENTFERNEN"
        }
    }
    
    # Wenn Benutzer nicht in Gruppe ist, entfernen
    if (-not $shouldKeep) {
        if (-not $WhatIf) {
            try {
                Remove-Printer -Name $printerName -ErrorAction SilentlyContinue
                Write-DebugLog "  -> ERFOLG: Drucker entfernt"
            } catch {
                try {
                    Remove-Printer -Name $printerName -Force -ErrorAction SilentlyContinue
                    Write-DebugLog "  -> ERFOLG: Drucker mit Force entfernt"
                } catch {
                    Write-DebugLog "  -> FEHLER: Entfernen fehlgeschlagen: $($_.Exception.Message)"
                }
            }
        } else {
            Write-DebugLog "  -> [WHATIF] Würde Drucker entfernen"
        }
    }
}

Write-DebugLog "=== Ende ==="
Write-Host "Debug-Log geschrieben nach: $logFile" -ForegroundColor Yellow

exit 0
