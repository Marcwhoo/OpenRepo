# ==================================================================
# Phase 2: XML-Export der Drucker von <PRINT-SERVER-2>
# Exportiert Drucker und Ports im CliXML-Format
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$SourceServer = "<PRINT-SERVER-2>"
$OutputDir = $PSScriptRoot
$OutputFilePrinters = Join-Path $OutputDir "2.2-Export-<PRINT-SERVER-2>-Printers.xml"
$OutputFilePorts = Join-Path $OutputDir "2.2-Export-<PRINT-SERVER-2>-Ports.xml"
$LogFile = "$OutputDir\Logs\2.2-Export-<PRINT-SERVER-2>_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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

Write-Log "=== Export <PRINT-SERVER-2> gestartet ===" "INFO"
Write-Log "Quell-Server: $SourceServer" "INFO"
Write-Log "Ziel-Datei Drucker: $OutputFilePrinters" "INFO"
Write-Log "Ziel-Datei Ports: $OutputFilePorts" "INFO"

# Prüfe ob Server erreichbar ist
Write-Host ""
Write-Host "Prüfe Verbindung zu $SourceServer..." -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName $SourceServer -Count 1 -Quiet)) {
    Write-Log "Server $SourceServer ist nicht erreichbar!" "ERROR"
    Write-Host "FEHLER: Server $SourceServer ist nicht erreichbar!" -ForegroundColor Red
    exit 1
}
Write-Host "Server ist erreichbar" -ForegroundColor Green

# Exportiere Drucker
Write-Host ""
Write-Host "Exportiere Drucker..." -ForegroundColor Cyan
try {
    $printers = Get-Printer -ComputerName $SourceServer -Full -ErrorAction Stop
    Write-Host "Gefundene Drucker: $($printers.Count)" -ForegroundColor Green
    
    if ($printers.Count -eq 0) {
        Write-Log "KEINE Drucker auf $SourceServer gefunden!" "WARNING"
        Write-Host "WARNUNG: Keine Drucker gefunden!" -ForegroundColor Yellow
    }
    else {
        $printers | Export-Clixml -Path $OutputFilePrinters -Force
        Write-Log "Drucker exportiert: $($printers.Count)" "SUCCESS"
        Write-Host "Drucker exportiert: $($printers.Count)" -ForegroundColor Green
        
        $fileSize = (Get-Item $OutputFilePrinters).Length / 1KB
        Write-Host "Datei: $OutputFilePrinters ($([math]::Round($fileSize, 2)) KB)" -ForegroundColor Gray
    }
}
catch {
    Write-Log "FEHLER beim Exportieren der Drucker: $($_.Exception.Message)" "ERROR"
    Write-Host "FEHLER beim Exportieren der Drucker: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Exportiere Ports
Write-Host ""
Write-Host "Exportiere Ports..." -ForegroundColor Cyan
try {
    $ports = Get-PrinterPort -ComputerName $SourceServer -ErrorAction Stop
    Write-Host "Gefundene Ports: $($ports.Count)" -ForegroundColor Green
    
    if ($ports.Count -eq 0) {
        Write-Log "KEINE Ports auf $SourceServer gefunden!" "WARNING"
        Write-Host "WARNUNG: Keine Ports gefunden!" -ForegroundColor Yellow
    }
    else {
        $ports | Export-Clixml -Path $OutputFilePorts -Force
        Write-Log "Ports exportiert: $($ports.Count)" "SUCCESS"
        Write-Host "Ports exportiert: $($ports.Count)" -ForegroundColor Green
        
        $fileSize = (Get-Item $OutputFilePorts).Length / 1KB
        Write-Host "Datei: $OutputFilePorts ($([math]::Round($fileSize, 2)) KB)" -ForegroundColor Gray
    }
}
catch {
    Write-Log "FEHLER beim Exportieren der Ports: $($_.Exception.Message)" "ERROR"
    Write-Host "FEHLER beim Exportieren der Ports: $($_.Exception.Message)" -ForegroundColor Red
    # Ports sind optional, kein Exit
}

Write-Host ""
Write-Host "=== Export abgeschlossen ===" -ForegroundColor Green
Write-Host "Drucker-Datei: $OutputFilePrinters" -ForegroundColor Cyan
Write-Host "Ports-Datei: $OutputFilePorts" -ForegroundColor Cyan
Write-Log "=== Export <PRINT-SERVER-2> abgeschlossen ===" "INFO"

