# Client-Script zum Entfernen von Druckern, wenn Benutzer nicht mehr in Sicherheitsgruppen sind
# Dieses Script sollte per GPO als Startup/Logon Script verteilt werden
# Es funktioniert dynamisch mit allen Druckern, auch wenn neue hinzugefügt werden

param(
    [Parameter(Mandatory=$false)]
    [string]$PrintServer = "<PRINT-SERVER-1>-01",
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Logging-Funktion
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Schreibe in Event Log (optional)
    try {
        if (-not (Get-EventLog -LogName Application -Source "PrinterCleanup" -ErrorAction SilentlyContinue)) {
            New-EventLog -LogName Application -Source "PrinterCleanup" -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName Application -Source "PrinterCleanup" -EntryType Information -EventId 1000 -Message $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Event Log nicht verfügbar, überspringen
    }
}

# Start Logging
Write-Log "=== Starte Drucker-Bereinigung ===" "INFO"
Write-Log "Druckerserver: $PrintServer" "INFO"
Write-Log "Benutzer: $env:USERNAME" "INFO"

# Hole Domain-Informationen
try {
    $domainName = (Get-ADDomain).DNSRoot
} catch {
    Write-Log "FEHLER: Konnte Domain-Informationen nicht abrufen: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Hole alle Gruppen des Benutzers (mit SIDs)
try {
    $userGroups = Get-ADUser -Identity $env:USERNAME -Properties MemberOf | Select-Object -ExpandProperty MemberOf
    $userGroupSids = @()
    $userGroupNames = @()
    foreach ($groupDN in $userGroups) {
        try {
            $group = Get-ADGroup -Identity $groupDN -Properties SID
            $userGroupSids += $group.SID.Value
            $userGroupNames += $group.Name
        } catch {
            # Gruppe nicht gefunden, überspringen
        }
    }
    Write-Log "Benutzer ist in $($userGroupSids.Count) Gruppen" "INFO"
} catch {
    Write-Log "WARNUNG: Konnte Gruppen des Benutzers nicht abrufen: $($_.Exception.Message)" "WARNING"
    $userGroupSids = @()
    $userGroupNames = @()
}

# Hole alle Drucker vom Server
try {
    $printers = Get-Printer -ComputerName $PrintServer -ErrorAction Stop | Where-Object { $_.Shared -eq $true }
    Write-Log "Gefunden: $($printers.Count) geteilte Drucker auf Server" "INFO"
} catch {
    Write-Log "FEHLER: Konnte Drucker vom Server nicht abrufen: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Hole alle lokalen Drucker des Benutzers
try {
    $localPrinters = Get-Printer -ErrorAction Stop | Where-Object { 
        $_.Name -notlike "Microsoft*" -and 
        $_.Name -notlike "Fax*" -and
        $_.Name -notlike "OneNote*"
    }
    Write-Log "Gefunden: $($localPrinters.Count) lokale Drucker" "INFO"
} catch {
    Write-Log "FEHLER: Konnte lokale Drucker nicht abrufen: $($_.Exception.Message)" "ERROR"
    exit 1
}

$removedCount = 0
$errorCount = 0
$skippedCount = 0

foreach ($localPrinter in $localPrinters) {
    $printerName = $localPrinter.Name
    $printerPath = $localPrinter.PortName
    
    # Prüfe, ob der Drucker vom Print-Server kommt
    if ($printerPath -notlike "\\$PrintServer\*") {
        $skippedCount++
        continue
    }
    
    # Extrahiere den Druckernamen aus dem UNC-Pfad
    # Der Port-Name ist normalerweise der UNC-Pfad: \\Server\DruckerName
    $printerShareName = $printerPath -replace "\\$PrintServer\\", ""
    
    # Finde den entsprechenden Drucker auf dem Server
    # Prüfe sowohl ShareName als auch Name (da diese unterschiedlich sein können)
    $serverPrinter = $printers | Where-Object { 
        $_.ShareName -eq $printerShareName -or 
        $_.Name -eq $printerShareName -or
        $_.Name -eq $printerName
    }
    
    if (-not $serverPrinter) {
        # Drucker existiert nicht mehr auf dem Server - entfernen
        Write-Log "ENTFERNEN: $printerName (existiert nicht mehr auf Server)" "INFO"
        if (-not $WhatIf) {
            try {
                Remove-Printer -Name $printerName -ErrorAction Stop
                Write-Log "ERFOLG: Drucker entfernt: $printerName" "INFO"
                $removedCount++
            } catch {
                Write-Log "FEHLER beim Entfernen von $printerName : $($_.Exception.Message)" "ERROR"
                $errorCount++
            }
        }
        continue
    }
    
    # Prüfe, ob der Druckername einer Sicherheitsgruppe entspricht
    # Der Gruppenname sollte dem Druckernamen entsprechen (wie in der GPO konfiguriert)
    $groupName = $serverPrinter.Name
    
    # Suche nach einer Gruppe mit diesem Namen
    try {
        $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        if ($group) {
            # Prüfe, ob der Benutzer in dieser Gruppe ist
            if ($userGroupSids -notcontains $group.SID.Value) {
                # Benutzer ist nicht in der Gruppe - Drucker entfernen
                Write-Log "ENTFERNEN: $printerName (Benutzer nicht in Gruppe: $groupName)" "INFO"
                if (-not $WhatIf) {
                    try {
                        Remove-Printer -Name $printerName -ErrorAction Stop
                        Write-Log "ERFOLG: Drucker entfernt: $printerName (Gruppe: $groupName)" "INFO"
                        $removedCount++
                    } catch {
                        Write-Log "FEHLER beim Entfernen von $printerName : $($_.Exception.Message)" "ERROR"
                        $errorCount++
                    }
                }
            } else {
                # Benutzer ist in der Gruppe - Drucker behalten
                Write-Log "BEHALTEN: $printerName (Benutzer in Gruppe: $groupName)" "DEBUG"
            }
        } else {
            # Gruppe nicht gefunden - könnte ein neuer Drucker sein, der noch keine Gruppe hat
            # In diesem Fall behalten wir den Drucker (wird später von der GPO verwaltet)
            Write-Log "ÜBERSPRUNGEN: $printerName (Keine Sicherheitsgruppe gefunden: $groupName)" "DEBUG"
            $skippedCount++
        }
    } catch {
        # Fehler beim Abrufen der Gruppe - überspringen
        Write-Log "FEHLER beim Abrufen der Gruppe für $printerName : $($_.Exception.Message)" "WARNING"
        $skippedCount++
    }
}

Write-Log "=== Zusammenfassung ===" "INFO"
Write-Log "Entfernte Drucker: $removedCount" "INFO"
Write-Log "Fehler: $errorCount" "INFO"
Write-Log "Übersprungen: $skippedCount" "INFO"

if ($WhatIf) {
    Write-Log "WhatIf-Modus: Keine Änderungen vorgenommen" "INFO"
}
