# ==================================================================
# Phase 1: Bestandsaufnahme aller Drucker von alten Servern
# Erfasst alle Drucker von <PRINT-SERVER-1>, <PRINT-SERVER-2> und <PRINT-SERVER-3>
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OldServers = @("<PRINT-SERVER-1>", "<PRINT-SERVER-2>", "<PRINT-SERVER-3>")
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\1.1-Bestandsaufnahme-Drucker_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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

Write-Log "=== Bestandsaufnahme Drucker gestartet ===" "INFO"
Write-Log "Alte Server: $($OldServers -join ', ')" "INFO"

$allPrinters = @()

foreach ($server in $OldServers) {
    Write-Host ""
    Write-Host "=== Server: $server ===" -ForegroundColor Cyan
    Write-Log "Erfasse Drucker von Server: $server" "INFO"
    
    try {
        # Prüfe ob Server erreichbar ist
        if (-not (Test-Connection -ComputerName $server -Count 1 -Quiet)) {
            Write-Log "Server $server ist nicht erreichbar!" "ERROR"
            Write-Host "WARNUNG: Server $server ist nicht erreichbar!" -ForegroundColor Yellow
            continue
        }
        
        # Hole alle Drucker vom Server
        $printers = Get-Printer -ComputerName $server -Full -ErrorAction Stop
        Write-Log "Gefundene Drucker auf $server : $($printers.Count)" "INFO"
        Write-Host "Gefundene Drucker: $($printers.Count)" -ForegroundColor Green
        
        foreach ($printer in $printers) {
            try {
                Write-Log "  Verarbeite Drucker: $($printer.Name)" "INFO"
                
                # Hole Port-Informationen
                $portInfo = $null
                $portAddress = ""
                $portType = ""
                
                if ($printer.PortName) {
                    try {
                        $port = Get-PrinterPort -ComputerName $server -Name $printer.PortName -ErrorAction SilentlyContinue
                        if ($port) {
                            $portType = $port.PrinterPortType
                            if ($port.PrinterHostAddress) {
                                $portAddress = $port.PrinterHostAddress
                            }
                            elseif ($port.PortAddress) {
                                $portAddress = $port.PortAddress
                            }
                        }
                    }
                    catch {
                        # Port-Informationen nicht verfügbar
                    }
                }
                
                # Erstelle Drucker-Objekt für CSV
                $printerInfo = [PSCustomObject]@{
                    Server = $server
                    PrinterName = $printer.Name
                    ShareName = if ($printer.ShareName) { $printer.ShareName } else { "" }
                    Shared = $printer.Shared
                    Published = $printer.Published
                    DriverName = if ($printer.DriverName) { $printer.DriverName } else { "" }
                    DriverVersion = if ($printer.DriverVersion) { $printer.DriverVersion } else { "" }
                    PortName = if ($printer.PortName) { $printer.PortName } else { "" }
                    PortType = $portType
                    PortAddress = $portAddress
                    Location = if ($printer.Location) { $printer.Location } else { "" }
                    Comment = if ($printer.Comment) { $printer.Comment } else { "" }
                    Status = $printer.PrinterStatus
                }
                
                $allPrinters += $printerInfo
            }
            catch {
                Write-Log "Fehler beim Verarbeiten von Drucker $($printer.Name): $($_.Exception.Message)" "WARNING"
            }
        }
        
        Write-Log "Gefunden: $($printers.Count) Drucker auf $server" "SUCCESS"
    }
    catch {
        Write-Log "FEHLER beim Abrufen der Drucker von $server : $($_.Exception.Message)" "ERROR"
        Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Exportiere Ergebnisse
if ($allPrinters.Count -gt 0) {
    $csvFile = Join-Path $OutputDir "1.1-Drucker-Bestandsaufnahme.csv"
    $allPrinters | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "CSV-Export erstellt: $csvFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Zusammenfassung ===" -ForegroundColor Green
    Write-Host "Gesamt gefundene Drucker: $($allPrinters.Count)" -ForegroundColor Green
    
    # Gruppiere nach Server
    Write-Host ""
    Write-Host "=== Drucker nach Server ===" -ForegroundColor Yellow
    foreach ($server in $OldServers) {
        $serverPrinters = $allPrinters | Where-Object { $_.Server -eq $server }
        Write-Host "  $server : $($serverPrinters.Count) Drucker" -ForegroundColor Cyan
    }
}
else {
    Write-Host "KEINE Drucker gefunden!" -ForegroundColor Yellow
    Write-Log "KEINE Drucker gefunden" "WARNING"
    
    # Erstelle leere CSV-Datei trotzdem
    $csvFile = Join-Path $OutputDir "1.1-Drucker-Bestandsaufnahme.csv"
    $allPrinters | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Leere CSV-Datei erstellt: $csvFile" "INFO"
}

Write-Host ""
Write-Host "Export-Datei: $(Join-Path $OutputDir '1.1-Drucker-Bestandsaufnahme.csv')" -ForegroundColor Cyan

Write-Log "=== Bestandsaufnahme abgeschlossen ===" "INFO"

