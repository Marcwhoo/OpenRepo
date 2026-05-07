# ==================================================================
# Phase 4: XML-Dateien anpassen für Import (EINFACHE VERSION)
# Bearbeitet XML-Dateien direkt als Text/XML, ohne Objekte zu deserialisieren
# Erstellt NEUE Import-XML-Dateien (überschreibt Originale NICHT)
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = $ScriptDir
$NewServer = "<PRINT-SERVER-1>-01"

# Validierung
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    Write-Error "FEHLER: OutputDir konnte nicht bestimmt werden."
    exit 1
}

# CSV-Dateien
$DruckerZuordnungCSV = Join-Path $OutputDir "3.2-Zuordnung-Drucker-Namen.csv"
$PortZuordnungCSV = Join-Path $OutputDir "3.3-Zuordnung-Port-Namen.csv"
$PortEntfernenCSV = Join-Path $OutputDir "3.4-Ports-Entfernen.csv"

# XML-Dateien (Originale)
$XMLFiles = @(
    @{ Server = "<PRINT-SERVER-1>"; PrintersFile = "2.1-Export-<PRINT-SERVER-1>-Printers.xml"; PortsFile = "2.1-Export-<PRINT-SERVER-1>-Ports.xml" }
    @{ Server = "<PRINT-SERVER-2>"; PrintersFile = "2.2-Export-<PRINT-SERVER-2>-Printers.xml"; PortsFile = "2.2-Export-<PRINT-SERVER-2>-Ports.xml" }
    @{ Server = "<PRINT-SERVER-3>"; PrintersFile = "2.3-Export-<PRINT-SERVER-3>-Printers.xml"; PortsFile = "2.3-Export-<PRINT-SERVER-3>-Ports.xml" }
)

# Log-Datei
$LogFile = Join-Path $OutputDir "Logs\4.1-Anpasse-XML-Dateien_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
if (-not (Test-Path "$OutputDir\Logs")) { New-Item -ItemType Directory -Path "$OutputDir\Logs" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

Write-Log "=== XML-Dateien anpassen gestartet ===" "INFO"
Write-Log "Neuer Server: $NewServer" "INFO"

# Prüfe CSV-Dateien
Write-Host ""
Write-Host "Prüfe CSV-Dateien..." -ForegroundColor Cyan
$missingFiles = @()
if (-not (Test-Path $DruckerZuordnungCSV)) { $missingFiles += $DruckerZuordnungCSV }
if (-not (Test-Path $PortZuordnungCSV)) { $missingFiles += $PortZuordnungCSV }
if (-not (Test-Path $PortEntfernenCSV)) { $missingFiles += $PortEntfernenCSV }

if ($missingFiles.Count -gt 0) {
    Write-Log "FEHLER: Folgende CSV-Dateien fehlen:" "ERROR"
    foreach ($file in $missingFiles) {
        Write-Log "  - $file" "ERROR"
    }
    Write-Host "FEHLER: CSV-Dateien fehlen!" -ForegroundColor Red
    exit 1
}
Write-Host "Alle CSV-Dateien gefunden" -ForegroundColor Green

# Lade Zuordnungslisten
Write-Host ""
Write-Host "Lade Zuordnungslisten..." -ForegroundColor Cyan
try {
    $druckerZuordnung = Import-Csv -Path $DruckerZuordnungCSV -Delimiter ";" -Encoding UTF8
    Write-Log "Drucker-Zuordnung geladen: $($druckerZuordnung.Count) Einträge" "INFO"
    Write-Host "  Drucker-Zuordnung: $($druckerZuordnung.Count) Einträge" -ForegroundColor Green
    
    $portZuordnung = Import-Csv -Path $PortZuordnungCSV -Delimiter ";" -Encoding UTF8
    Write-Log "Port-Zuordnung geladen: $($portZuordnung.Count) Einträge" "INFO"
    Write-Host "  Port-Zuordnung: $($portZuordnung.Count) Einträge" -ForegroundColor Green
    
    $portEntfernen = Import-Csv -Path $PortEntfernenCSV -Delimiter ";" -Encoding UTF8
    Write-Log "Port-Entfernen-Liste geladen: $($portEntfernen.Count) Einträge" "INFO"
    Write-Host "  Port-Entfernen-Liste: $($portEntfernen.Count) Einträge" -ForegroundColor Green
} catch {
    Write-Log "FEHLER beim Laden der CSV-Dateien: $($_.Exception.Message)" "ERROR"
    Write-Host "FEHLER beim Laden der CSV-Dateien!" -ForegroundColor Red
    exit 1
}

# Erstelle Mappings
Write-Host ""
Write-Host "Erstelle Mappings..." -ForegroundColor Cyan

$druckerMapping = @{}
foreach ($entry in $druckerZuordnung) {
    if ($entry.Status -eq "OK") {
        $key = $entry.Server + '|' + $entry.OldPrinterName
        $druckerMapping[$key] = @{
            NewPrinterName = $entry.NewPrinterName
            NewShareName = $entry.NewShareName
            OldPrinterName = $entry.OldPrinterName
        }
    }
}
Write-Log "Drucker-Mapping erstellt: $($druckerMapping.Count) Einträge" "INFO"

$portMapping = @{}
foreach ($entry in $portZuordnung) {
    if ($entry.Status -eq "OK" -or $entry.Status -eq "IP_INKONSISTENT") {
        $key = $entry.Server + '|' + $entry.OldPortName
        $portMapping[$key] = @{
            NewPortName = $entry.NewPortName
            IPAddress = $entry.IPAddress
            PortNumber = $entry.PortNumber
            Protocol = $entry.Protocol
            IsWSD = $entry.IsWSD -eq "True"
        }
    }
}
Write-Log "Port-Mapping erstellt: $($portMapping.Count) Einträge" "INFO"

$portEntfernenMapping = @{}
foreach ($entry in $portEntfernen) {
    $key = $entry.Server + '|' + $entry.PortName
    $portEntfernenMapping[$key] = $true
}
Write-Log "Port-Entfernen-Mapping erstellt: $($portEntfernenMapping.Count) Einträge" "INFO"

# Verarbeite jede XML-Datei
foreach ($xmlFileInfo in $XMLFiles) {
    $server = $xmlFileInfo.Server
    $printersFile = $xmlFileInfo.PrintersFile
    $portsFile = $xmlFileInfo.PortsFile
    
    $printersPath = Join-Path $OutputDir $printersFile
    $portsPath = Join-Path $OutputDir $portsFile
    
    # Neue Import-Dateien
    $newPrintersFile = $printersFile -replace "^2\.\d-Export-", "4.1-Import-"
    $newPortsFile = $portsFile -replace "^2\.\d-Export-", "4.1-Import-"
    $newPrintersPath = Join-Path $OutputDir $newPrintersFile
    $newPortsPath = Join-Path $OutputDir $newPortsFile
    
    Write-Host ""
    Write-Host "=== Verarbeite $server ===" -ForegroundColor Cyan
    Write-Log "=== Verarbeite $server ===" "INFO"
    
    # Prüfe ob Original-Dateien existieren
    if (-not (Test-Path $printersPath)) {
        Write-Log "WARNUNG: Drucker-XML nicht gefunden: $printersPath" "WARNING"
        Write-Host "  WARNUNG: Drucker-XML nicht gefunden" -ForegroundColor Yellow
        continue
    }
    if (-not (Test-Path $portsPath)) {
        Write-Log "WARNUNG: Ports-XML nicht gefunden: $portsPath" "WARNING"
        Write-Host "  WARNUNG: Ports-XML nicht gefunden" -ForegroundColor Yellow
        continue
    }
    
    # Lade XML-Dateien als XML
    Write-Host ""
    Write-Host "Lade und bearbeite XML-Dateien..." -ForegroundColor Cyan
    
    try {
        # Drucker-XML bearbeiten
        [xml]$printersXml = Get-Content -Path $printersPath -Encoding UTF8
        
        # Namespace-Manager für XPath
        $nsManager = New-Object System.Xml.XmlNamespaceManager($printersXml.NameTable)
        $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
        
        $changedPrinters = 0
        
        foreach ($obj in $printersXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager)) {
            $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
            if ($nameProp) {
                $printerName = $nameProp.InnerText
                $key = $server + '|' + $printerName
                
                # Ändere ComputerName für ALLE Drucker (auch ohne Zuordnung)
                $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager)
                if ($compNameProp) {
                    $compNameProp.InnerText = $NewServer
                }
                
                if ($druckerMapping.ContainsKey($key)) {
                    $mapping = $druckerMapping[$key]
                    
                    # Ändere Name
                    $newPrinterName = $mapping.NewPrinterName
                    $nameProp.InnerText = $newPrinterName
                    
                    # WICHTIG: ShareName wird IMMER auf den neuen Druckernamen gesetzt
                    $shareNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ShareName']", $nsManager)
                    if ($shareNameProp) {
                        # ShareName-Element existiert bereits - setze auf Druckernamen
                        $shareNameProp.InnerText = $newPrinterName
                    } else {
                        # ShareName-Element existiert nicht - erstelle es
                        $propsNode = $obj.SelectSingleNode(".//ps:Props", $nsManager)
                        if ($propsNode) {
                            $newShareNameNode = $printersXml.CreateElement("S", "http://schemas.microsoft.com/powershell/2004/04")
                            $newShareNameNode.SetAttribute("N", "ShareName")
                            $newShareNameNode.InnerText = $newPrinterName
                            $propsNode.AppendChild($newShareNameNode) | Out-Null
                        }
                    }
                    
                    # Füge alten Namen in Comment ein
                    $commentProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Comment']", $nsManager)
                    if ($commentProp) {
                        $oldComment = $commentProp.InnerText
                        if ([string]::IsNullOrWhiteSpace($oldComment)) {
                            $commentProp.InnerText = "Alter Name: $($mapping.OldPrinterName)"
                        } else {
                            $commentProp.InnerText = "$oldComment | Alter Name: $($mapping.OldPrinterName)"
                        }
                    }
                    
                    # Ändere PortName
                    $portNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PortName']", $nsManager)
                    if ($portNameProp) {
                        $oldPortName = $portNameProp.InnerText
                        $portKey = $server + '|' + $oldPortName
                        if ($portMapping.ContainsKey($portKey)) {
                            $portMap = $portMapping[$portKey]
                            $portNameProp.InnerText = $portMap.NewPortName
                        }
                    }
                    
                    $changedPrinters++
                    Write-Log "  Drucker angepasst: '$printerName' -> '$($mapping.NewPrinterName)'" "INFO"
                } else {
                    # Drucker ohne Zuordnung - nur ComputerName wurde bereits geändert
                    # Stelle sicher, dass auch diese Drucker einen ShareName haben (gleich Druckername)
                    $shareNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ShareName']", $nsManager)
                    if ($shareNameProp) {
                        # ShareName-Element existiert bereits - setze auf Druckernamen
                        $shareNameProp.InnerText = $printerName
                    } else {
                        # ShareName-Element existiert nicht - erstelle es
                        $propsNode = $obj.SelectSingleNode(".//ps:Props", $nsManager)
                        if ($propsNode) {
                            $newShareNameNode = $printersXml.CreateElement("S", "http://schemas.microsoft.com/powershell/2004/04")
                            $newShareNameNode.SetAttribute("N", "ShareName")
                            $newShareNameNode.InnerText = $printerName
                            $propsNode.AppendChild($newShareNameNode) | Out-Null
                        }
                    }
                    Write-Log "  Drucker ohne Zuordnung behalten: '$printerName' (ComputerName und ShareName geändert)" "INFO"
                }
            }
        }
        
        # Speichere neue Drucker-XML
        $printersXml.Save($newPrintersPath)
        Write-Log "Drucker-XML gespeichert: $newPrintersFile ($changedPrinters Drucker)" "SUCCESS"
        Write-Host "  Gespeichert: $newPrintersFile ($changedPrinters Drucker)" -ForegroundColor Green
        
        # Ports-XML bearbeiten
        [xml]$portsXml = Get-Content -Path $portsPath -Encoding UTF8
        
        # Namespace-Manager für XPath
        $nsManager2 = New-Object System.Xml.XmlNamespaceManager($portsXml.NameTable)
        $nsManager2.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
        
        $changedPorts = 0
        $removedPorts = 0
        
        foreach ($obj in $portsXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager2)) {
            $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
            if ($nameProp) {
                $portName = $nameProp.InnerText
                $key = $server + '|' + $portName
                
                # Prüfe ob Port entfernt werden soll
                if ($portEntfernenMapping.ContainsKey($key)) {
                    $removedPorts++
                    $obj.ParentNode.RemoveChild($obj) | Out-Null
                    Write-Log "  Port entfernt: '$portName'" "INFO"
                    continue
                }
                
                # Ändere ComputerName für ALLE Ports (auch ohne Zuordnung)
                $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager2)
                if ($compNameProp) {
                    $compNameProp.InnerText = $NewServer
                }
                
                # Prüfe ob Port angepasst werden soll
                if ($portMapping.ContainsKey($key)) {
                    $mapping = $portMapping[$key]
                    
                    # Ändere Name
                    $nameProp.InnerText = $mapping.NewPortName
                    
                    # WSD-Port zu TCP/IP konvertieren
                    if ($mapping.IsWSD) {
                        Write-Log "  WSD-Port konvertiert: '$portName' -> '$($mapping.NewPortName)'" "INFO"
                        $monitorProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PortMonitor']", $nsManager2)
                        if ($monitorProp) {
                            $monitorProp.InnerText = "TCPMON.DLL"
                        }
                    }
                    
                    # Setze IP-Adresse und Port-Einstellungen
                    $hostAddrProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PrinterHostAddress']", $nsManager2)
                    if ($hostAddrProp -and $mapping.IPAddress) {
                        $hostAddrProp.InnerText = $mapping.IPAddress
                    }
                    
                    $portNumProp = $obj.SelectSingleNode(".//ps:Props/ps:U32[@N='PortNumber']", $nsManager2)
                    if ($portNumProp -and $mapping.PortNumber) {
                        $portNumProp.InnerText = $mapping.PortNumber
                    }
                    
                    $protocolProp = $obj.SelectSingleNode(".//ps:Props/ps:U32[@N='Protocol']", $nsManager2)
                    if ($protocolProp -and $mapping.Protocol) {
                        $protocolProp.InnerText = $mapping.Protocol
                    }
                    
                    $changedPorts++
                    Write-Log "  Port angepasst: '$portName' -> '$($mapping.NewPortName)'" "INFO"
                }
            }
        }
        
        # Speichere neue Ports-XML
        $portsXml.Save($newPortsPath)
        Write-Log "Ports-XML gespeichert: $newPortsFile ($changedPorts Ports, $removedPorts entfernt)" "SUCCESS"
        Write-Host "  Gespeichert: $newPortsFile ($changedPorts Ports, $removedPorts entfernt)" -ForegroundColor Green
        
    } catch {
        Write-Log "FEHLER beim Bearbeiten der XML-Dateien: $($_.Exception.Message)" "ERROR"
        Write-Host "  FEHLER beim Bearbeiten!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== XML-Anpassung abgeschlossen ===" -ForegroundColor Green
Write-Log "=== XML-Anpassung abgeschlossen ===" "INFO"
Write-Host ""
Write-Host "Neue Import-XML-Dateien wurden erstellt:" -ForegroundColor Cyan
Write-Host "  - 4.1-Import-<PRINT-SERVER-1>-Printers.xml" -ForegroundColor Gray
Write-Host "  - 4.1-Import-<PRINT-SERVER-1>-Ports.xml" -ForegroundColor Gray
Write-Host "  - 4.1-Import-<PRINT-SERVER-2>-Printers.xml" -ForegroundColor Gray
Write-Host "  - 4.1-Import-<PRINT-SERVER-2>-Ports.xml" -ForegroundColor Gray
Write-Host "  - 4.1-Import-<PRINT-SERVER-3>-Printers.xml" -ForegroundColor Gray
Write-Host "  - 4.1-Import-<PRINT-SERVER-3>-Ports.xml" -ForegroundColor Gray
Write-Host ""
Write-Host "Die originalen Export-Dateien wurden NICHT verändert." -ForegroundColor Yellow

