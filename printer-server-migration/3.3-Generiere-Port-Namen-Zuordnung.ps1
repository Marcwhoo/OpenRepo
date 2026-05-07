# ==================================================================
# Phase 3: Generiere Zuordnungsliste alter → neuer Port-Namen
# Erstellt eine Liste mit alten und neuen Port-Namen
# Format: IP-Adresse + Neuer Druckername
# 
# WICHTIG: Dieses Skript nimmt KEINE Änderungen an den alten Servern vor!
# Es erstellt nur Zuordnungslisten für die XML-Bearbeitung.
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$ZuordnungsDatei = Join-Path $OutputDir "3.2-Zuordnung-Drucker-Namen.csv"
$LogFile = "$OutputDir\Logs\3.3-Generiere-Port-Namen-Zuordnung_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# XML-Dateien
$PortsFiles = @(
    @{ File = "2.1-Export-<PRINT-SERVER-1>-Ports.xml"; Server = "<PRINT-SERVER-1>" },
    @{ File = "2.2-Export-<PRINT-SERVER-2>-Ports.xml"; Server = "<PRINT-SERVER-2>" },
    @{ File = "2.3-Export-<PRINT-SERVER-3>-Ports.xml"; Server = "<PRINT-SERVER-3>" }
)

$PrintersFiles = @(
    @{ File = "2.1-Export-<PRINT-SERVER-1>-Printers.xml"; Server = "<PRINT-SERVER-1>" },
    @{ File = "2.2-Export-<PRINT-SERVER-2>-Printers.xml"; Server = "<PRINT-SERVER-2>" },
    @{ File = "2.3-Export-<PRINT-SERVER-3>-Printers.xml"; Server = "<PRINT-SERVER-3>" }
)

# Erstelle Verzeichnisse
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (-not (Test-Path "$OutputDir\Logs")) { New-Item -ItemType Directory -Path "$OutputDir\Logs" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

# Funktion zum Extrahieren von IP-Adressen aus einem String
function Get-IPFromString {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    # Suche nach IP-Adresse im Format xxx.xxx.xxx.xxx
    if ($Text -match '\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b') {
        return $matches[1]
    }
    return $null
}

Write-Log "=== Generiere Port-Namen-Zuordnung gestartet ===" "INFO"

# Prüfe ob Zuordnungsdatei existiert
if (-not (Test-Path $ZuordnungsDatei)) {
    Write-Log "FEHLER: Zuordnungsdatei nicht gefunden: $ZuordnungsDatei" "ERROR"
    Write-Log "Bitte zuerst 3.2-Generiere-Drucker-Namen-Zuordnung.ps1 ausführen!" "ERROR"
    Write-Host "FEHLER: Zuordnungsdatei nicht gefunden!" -ForegroundColor Red
    exit 1
}

# Lade Drucker-Namen-Zuordnung
Write-Host ""
Write-Host "Lade Drucker-Namen-Zuordnung..." -ForegroundColor Cyan
try {
    $druckerZuordnung = Import-Csv -Path $ZuordnungsDatei -Delimiter ";" -Encoding UTF8
    Write-Log "Drucker-Zuordnung geladen: $($druckerZuordnung.Count) Einträge" "INFO"
    Write-Host "Geladen: $($druckerZuordnung.Count) Zuordnungen" -ForegroundColor Green
} catch {
    Write-Log "FEHLER beim Laden der Zuordnungsdatei: $($_.Exception.Message)" "ERROR"
    Write-Host "FEHLER beim Laden der Zuordnungsdatei!" -ForegroundColor Red
    exit 1
}

# Erstelle Mapping: Server|OldPrinterName -> NewPrinterName, PortAddress
$druckerMapping = @{}
foreach ($entry in $druckerZuordnung) {
    $key = "$($entry.Server)|$($entry.OldPrinterName)"
    $druckerMapping[$key] = @{
        NewPrinterName = $entry.NewPrinterName
        PortAddress = $entry.PortAddress
    }
}
Write-Log "Drucker-Mapping erstellt: $($druckerMapping.Count) Einträge" "INFO"

# Lade Drucker-XML-Dateien, um PortName-Zuordnungen zu finden
Write-Host ""
Write-Host "Lade Drucker-XML-Dateien..." -ForegroundColor Cyan
$printerPortMapping = @{}  # Server|PrinterName -> PortName
$usedPorts = @{}  # PortName -> Server (um nicht verwendete Ports zu finden)

foreach ($printerFileInfo in $PrintersFiles) {
    $printerFile = $printerFileInfo.File
    $server = $printerFileInfo.Server
    $printerFilePath = Join-Path $OutputDir $printerFile
    
    if (-not (Test-Path $printerFilePath)) {
        Write-Log "Drucker-XML nicht gefunden: $printerFilePath" "WARNING"
        continue
    }
    
    Write-Log "Lade Drucker-XML: $printerFile" "INFO"
    try {
        $printers = Import-Clixml -Path $printerFilePath
        
        foreach ($printer in $printers) {
            $printerName = $printer.Name
            $portName = $printer.PortName
            
            if (-not [string]::IsNullOrWhiteSpace($portName)) {
                $key = "$server|$printerName"
                $printerPortMapping[$key] = $portName
                $usedPorts[$portName] = $server
                Write-Log "  Gefunden: $printerName -> Port: $portName" "INFO"
            }
        }
    } catch {
        Write-Log "FEHLER beim Laden der Drucker-XML: $($_.Exception.Message)" "ERROR"
    }
}

Write-Log "Drucker-Port-Zuordnungen gefunden: $($printerPortMapping.Count)" "INFO"
Write-Log "Verwendete Ports: $($usedPorts.Count)" "INFO"

# Verarbeite Ports-XML-Dateien
Write-Host ""
Write-Host "Verarbeite Ports-XML-Dateien..." -ForegroundColor Cyan
$results = @()
$unusedPorts = @()  # Ports ohne zugehörigen Drucker

foreach ($portFileInfo in $PortsFiles) {
    $portFile = $portFileInfo.File
    $server = $portFileInfo.Server
    $portFilePath = Join-Path $OutputDir $portFile
    
    if (-not (Test-Path $portFilePath)) {
        Write-Log "Ports-XML nicht gefunden: $portFilePath" "WARNING"
        continue
    }
    
    Write-Host ""
    Write-Host "Verarbeite: $portFile" -ForegroundColor Cyan
    Write-Log "Verarbeite Ports-XML: $portFile" "INFO"
    
    try {
        $ports = Import-Clixml -Path $portFilePath
        
        foreach ($port in $ports) {
            $portName = $port.Name
            $portMonitor = $port.PortMonitor
            $portType = $port.PSTypeNames[0]
            $isWSD = $portMonitor -eq "WSD Port Monitor" -or $portName -like "WSD-*"
            $isTCPIP = $portType -like "*TcpIpPrinterPort*" -or $portMonitor -eq "TCPMON.DLL"
            $isLocal = $portType -like "*LocalPrinterPort*" -or $portMonitor -eq "Local Monitor"
            
            # Prüfe ob Port verwendet wird
            $isUsed = $usedPorts.ContainsKey($portName)
            
            # TCP/IP-Ports verarbeiten
            if ($isTCPIP) {
                $ipAddress = $port.PrinterHostAddress
                
                if ([string]::IsNullOrWhiteSpace($ipAddress)) {
                    Write-Log "  Überspringe Port $portName (keine IP-Adresse)" "WARNING"
                    if (-not $isUsed) {
                    # Port wird nicht in XML übernommen (keine IP-Adresse)
                    $unusedPorts += [PSCustomObject]@{
                        Server = $server
                        PortName = $portName
                        PortType = "TCP/IP"
                        PortMonitor = $portMonitor
                        Reason = "KEINE_IP_ADRESSE"
                        Action = "AUS_XML_ENTFERNEN"
                    }
                    }
                    continue
                }
                
                # Prüfe auf Inkonsistenz zwischen Port-Name und tatsächlicher IP-Adresse
                $ipInPortName = Get-IPFromString -Text $portName
                $ipInconsistency = $false
                if ($ipInPortName -and $ipInPortName -ne $ipAddress) {
                    $ipInconsistency = $true
                    Write-Log "  WARNUNG: Port-Name enthält IP $ipInPortName, aber tatsächliche IP ist $ipAddress" "WARNING"
                }
                
                # Finde zugehörigen Drucker über PortName
                $newPrinterName = ""
                $oldPrinterName = ""
                
                foreach ($printerKey in $printerPortMapping.Keys) {
                    if ($printerPortMapping[$printerKey] -eq $portName) {
                        # Extrahiere Server und Druckername aus dem Key
                        $parts = $printerKey -split '\|', 2
                        if ($parts.Length -eq 2 -and $parts[0] -eq $server) {
                            $oldPrinterName = $parts[1]
                            
                            # Finde neuen Druckernamen
                            $druckerKey = "$server|$oldPrinterName"
                            if ($druckerMapping.ContainsKey($druckerKey)) {
                                $newPrinterName = $druckerMapping[$druckerKey].NewPrinterName
                            }
                            break
                        }
                    }
                }
                
                # Erstelle neuen Port-Namen: IP-Adresse + Neuer Druckername
                # WICHTIG: Verwende IMMER die tatsächliche IP-Adresse (PrinterHostAddress), nicht die aus dem Port-Namen
                $newPortName = ""
                $status = ""
                
                if (-not [string]::IsNullOrWhiteSpace($newPrinterName)) {
                    $newPortName = "$ipAddress $newPrinterName"
                    $status = "OK"
                } elseif ($isUsed) {
                    # Port wird verwendet, aber kein neuer Druckername gefunden
                    $newPortName = $ipAddress
                    $status = "KEIN_NEUER_NAME"
                    Write-Log "  Port $portName wird verwendet, aber kein neuer Druckername gefunden" "WARNING"
                } else {
                    # Port wird nicht verwendet - aus XML entfernen, NICHT auf Server löschen
                    $newPortName = $ipAddress
                    $status = "NICHT_VERWENDET"
                    $unusedPorts += [PSCustomObject]@{
                        Server = $server
                        PortName = $portName
                        PortType = "TCP/IP"
                        PortMonitor = $portMonitor
                        IPAddress = $ipAddress
                        Reason = "KEIN_DRUCKER_ZUGEWIESEN"
                        Action = "AUS_XML_ENTFERNEN"
                    }
                    Write-Log "  Port $portName wird nicht verwendet (wird aus XML entfernt, NICHT auf Server gelöscht)" "WARNING"
                }
                
                if ($ipInconsistency) {
                    Write-Log "  Port: $portName -> $newPortName (IP korrigiert: $ipInPortName -> $ipAddress, Drucker: $oldPrinterName -> $newPrinterName, Status: $status)" "INFO"
                } else {
                    Write-Log "  Port: $portName -> $newPortName (Drucker: $oldPrinterName -> $newPrinterName, Status: $status)" "INFO"
                }
                
                $results += [PSCustomObject]@{
                    Server = $server
                    OldPortName = $portName
                    IPAddress = $ipAddress  # Tatsächliche IP-Adresse aus PrinterHostAddress
                    OldPrinterName = $oldPrinterName
                    NewPrinterName = $newPrinterName
                    NewPortName = $newPortName
                    PortMonitor = $portMonitor
                    PortNumber = $port.PortNumber
                    Protocol = $port.Protocol
                    Status = $status
                    IsWSD = $false
                    Action = if ($status -eq "NICHT_VERWENDET") { "AUS_XML_ENTFERNEN" } else { "UMBENENNEN" }
                }
            }
            # WSD-Ports verarbeiten
            elseif ($isWSD) {
                Write-Log "  WSD-Port gefunden: $portName" "INFO"
                
                # Finde zugehörigen Drucker über PortName
                $newPrinterName = ""
                $oldPrinterName = ""
                $ipAddress = ""
                
                foreach ($printerKey in $printerPortMapping.Keys) {
                    if ($printerPortMapping[$printerKey] -eq $portName) {
                        # Extrahiere Server und Druckername aus dem Key
                        $parts = $printerKey -split '\|', 2
                        if ($parts.Length -eq 2 -and $parts[0] -eq $server) {
                            $oldPrinterName = $parts[1]
                            
                            # Finde neuen Druckernamen und IP-Adresse
                            $druckerKey = "$server|$oldPrinterName"
                            if ($druckerMapping.ContainsKey($druckerKey)) {
                                $newPrinterName = $druckerMapping[$druckerKey].NewPrinterName
                                $ipAddress = $druckerMapping[$druckerKey].PortAddress
                            }
                            break
                        }
                    }
                }
                
                $status = ""
                $newPortName = ""
                $action = ""
                
                if (-not [string]::IsNullOrWhiteSpace($newPrinterName) -and -not [string]::IsNullOrWhiteSpace($ipAddress)) {
                    # Neuer TCP/IP-Port-Name: IP-Adresse + Neuer Druckername
                    $newPortName = "$ipAddress $newPrinterName"
                    $status = "ZU_TCPIP_KONVERTIEREN"
                    $action = "ZU_TCPIP_KONVERTIEREN"
                    Write-Log "  WSD-Port $portName -> TCP/IP-Port: $newPortName" "INFO"
                } elseif (-not [string]::IsNullOrWhiteSpace($oldPrinterName)) {
                    # Drucker gefunden, aber keine IP-Adresse
                    $status = "IP_ADRESSE_FEHLT"
                    $action = "IP_ADRESSE_ERFORDERLICH"
                    Write-Log "  WSD-Port ${portName}: Drucker gefunden, aber keine IP-Adresse in Zuordnung" "WARNING"
                } else {
                    # Kein Drucker gefunden
                    $status = "KEIN_DRUCKER"
                    $action = "AUS_XML_ENTFERNEN"
                    $unusedPorts += [PSCustomObject]@{
                        Server = $server
                        PortName = $portName
                        PortType = "WSD"
                        PortMonitor = $portMonitor
                        Reason = "KEIN_DRUCKER_ZUGEWIESEN"
                        Action = "AUS_XML_ENTFERNEN"
                    }
                    Write-Log "  WSD-Port $portName wird nicht verwendet (wird aus XML entfernt, NICHT auf Server gelöscht)" "WARNING"
                }
                
                $results += [PSCustomObject]@{
                    Server = $server
                    OldPortName = $portName
                    IPAddress = $ipAddress
                    OldPrinterName = $oldPrinterName
                    NewPrinterName = $newPrinterName
                    NewPortName = $newPortName
                    PortMonitor = $portMonitor
                    PortNumber = $null
                    Protocol = $null
                    Status = $status
                    IsWSD = $true
                    Action = $action
                }
            }
            # Lokale Ports (COM, LPT, FILE, etc.) - nicht umbenennen, aber dokumentieren
            elseif ($isLocal) {
                if (-not $isUsed) {
                    # Lokale Ports werden nicht in XML übernommen
                    $unusedPorts += [PSCustomObject]@{
                        Server = $server
                        PortName = $portName
                        PortType = "Lokal"
                        PortMonitor = $portMonitor
                        Reason = "KEIN_DRUCKER_ZUGEWIESEN"
                        Action = "AUS_XML_ENTFERNEN"
                    }
                }
                Write-Log "  Überspringe lokalen Port: $portName (Typ: $portType)" "INFO"
            }
            # Andere Port-Typen
            else {
                if (-not $isUsed) {
                    # Unbekannte Ports werden nicht in XML übernommen
                    $unusedPorts += [PSCustomObject]@{
                        Server = $server
                        PortName = $portName
                        PortType = "Unbekannt"
                        PortMonitor = $portMonitor
                        Reason = "KEIN_DRUCKER_ZUGEWIESEN"
                        Action = "AUS_XML_ENTFERNEN"
                    }
                }
                Write-Log "  Überspringe unbekannten Port: $portName (Typ: $portType, Monitor: $portMonitor)" "INFO"
            }
        }
    } catch {
        Write-Log "FEHLER beim Verarbeiten von $portFile : $($_.Exception.Message)" "ERROR"
        Write-Host "  FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Exportiere Ergebnisse
if ($results.Count -gt 0) {
    $csvFile = Join-Path $OutputDir "3.3-Zuordnung-Port-Namen.csv"
    $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Port-Zuordnungsliste erstellt: $csvFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Zusammenfassung ===" -ForegroundColor Green
    Write-Host "Verarbeitete Ports: $($results.Count)" -ForegroundColor Green
    
    $byServer = $results | Group-Object -Property Server
    foreach ($group in $byServer) {
        Write-Host "  $($group.Name): $($group.Count) Ports" -ForegroundColor Yellow
    }
    
    $okCount = ($results | Where-Object { $_.Status -eq "OK" }).Count
    $wsdCount = ($results | Where-Object { $_.IsWSD -eq $true }).Count
    $wsdConvertCount = ($results | Where-Object { $_.Action -eq "ZU_TCPIP_KONVERTIEREN" }).Count
    $noPrinterCount = ($results | Where-Object { $_.Status -eq "KEIN_DRUCKER" -or $_.Status -eq "NICHT_VERWENDET" }).Count
    $removeFromXmlCount = ($results | Where-Object { $_.Action -eq "AUS_XML_ENTFERNEN" }).Count
    
    Write-Host "  OK (TCP/IP): $okCount" -ForegroundColor Green
    Write-Host "  WSD-Ports: $wsdCount" -ForegroundColor Cyan
    Write-Host "  WSD -> TCP/IP: $wsdConvertCount" -ForegroundColor Cyan
    Write-Host "  Ohne Drucker: $noPrinterCount" -ForegroundColor Yellow
    Write-Host "  Aus XML entfernen: $removeFromXmlCount" -ForegroundColor Yellow
    
    Write-Host ""
    Write-Host "=== Beispiel-Zuordnungen ===" -ForegroundColor Cyan
    $examples = $results | Where-Object { $_.Status -eq "OK" } | Select-Object -First 5
    foreach ($example in $examples) {
        Write-Host "  Alt: $($example.OldPortName)" -ForegroundColor Gray
        Write-Host "  Neu: $($example.NewPortName)" -ForegroundColor Green
        Write-Host ""
    }
    
    if ($wsdConvertCount -gt 0) {
        Write-Host ""
        Write-Host "=== WSD-Ports die konvertiert werden müssen ===" -ForegroundColor Cyan
        $wsdExamples = $results | Where-Object { $_.Action -eq "ZU_TCPIP_KONVERTIEREN" } | Select-Object -First 5
        foreach ($example in $wsdExamples) {
            Write-Host "  WSD: $($example.OldPortName)" -ForegroundColor Gray
            Write-Host "  -> TCP/IP: $($example.NewPortName)" -ForegroundColor Green
            Write-Host ""
        }
    }
    
    Write-Host ""
    Write-Host "Export-Datei: $csvFile" -ForegroundColor Cyan
} else {
    Write-Host "KEINE Port-Zuordnungen erstellt!" -ForegroundColor Yellow
    Write-Log "KEINE Port-Zuordnungen erstellt" "ERROR"
}

# Exportiere Liste für Ports, die aus XML entfernt werden sollen
if ($unusedPorts.Count -gt 0) {
    $removeFile = Join-Path $OutputDir "3.4-Ports-Entfernen.csv"
    $unusedPorts | Export-Csv -Path $removeFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Port-Entfernen-Liste erstellt: $removeFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Ports die aus XML entfernt werden (NICHT auf Server gelöscht!) ===" -ForegroundColor Yellow
    Write-Host "WICHTIG: Diese Ports bleiben auf den alten Servern unverändert!" -ForegroundColor Cyan
    Write-Host "Sie werden nur aus den XML-Export-Dateien entfernt, bevor sie importiert werden." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Anzahl: $($unusedPorts.Count)" -ForegroundColor Yellow
    
    $byServer = $unusedPorts | Group-Object -Property Server
    foreach ($group in $byServer) {
        Write-Host "  $($group.Name): $($group.Count) Ports" -ForegroundColor Yellow
    }
    
    $byType = $unusedPorts | Group-Object -Property PortType
    foreach ($group in $byType) {
        Write-Host "  $($group.Name): $($group.Count) Ports" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Entfernen-Liste: $removeFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Keine Ports gefunden, die aus XML entfernt werden müssen." -ForegroundColor Green
}

Write-Log "=== Generiere Port-Namen-Zuordnung abgeschlossen ===" "INFO"

