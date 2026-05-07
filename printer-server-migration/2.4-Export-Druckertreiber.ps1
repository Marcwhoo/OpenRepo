# ==================================================================
# Phase 2.4: Export der Druckertreiber von allen alten Printservern
# Exportiert alle installierten Druckertreiber im CliXML-Format
# ==================================================================
# 
# Dieses Script exportiert alle Druckertreiber von:
# - <PRINT-SERVER-1>
# - <PRINT-SERVER-2>
# - <PRINT-SERVER-3>
#
# Die Treiber werden in separate XML-Dateien exportiert für jeden Server
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$SourceServers = @("<PRINT-SERVER-1>", "<PRINT-SERVER-2>", "<PRINT-SERVER-3>")
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\2.4-Export-Druckertreiber_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Verzeichnisse
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (-not (Test-Path "$OutputDir\Logs")) { New-Item -ItemType Directory -Path "$OutputDir\Logs" -Force | Out-Null }

# Logging-Funktion
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

Write-Host ""
Write-Host "=== EXPORT DER DRUCKERTREIBER ===" -ForegroundColor Cyan
Write-Log "=== Export Druckertreiber gestartet ===" "INFO"
Write-Host ""

# Prüfe ob PrintManagement Module verfügbar ist
Write-Log "Prüfe PrintManagement Module..." "INFO"
if (-not (Get-Module -ListAvailable -Name PrintManagement)) {
    Write-Log "FEHLER: PrintManagement Module nicht gefunden. Bitte installieren Sie es mit: Install-Module -Name PrintManagement" "ERROR"
    Write-Host "FEHLER: PrintManagement Module nicht gefunden!" -ForegroundColor Red
    exit 1
}

# Lade PrintManagement Module
try {
    Import-Module PrintManagement -ErrorAction Stop
    Write-Log "PrintManagement Module geladen" "SUCCESS"
} catch {
    Write-Log "FEHLER: PrintManagement Module konnte nicht geladen werden: $($_.Exception.Message)" "ERROR"
    Write-Host "FEHLER: PrintManagement Module konnte nicht geladen werden!" -ForegroundColor Red
    exit 1
}

$totalDrivers = 0
$totalServers = 0
$failedServers = @()

foreach ($SourceServer in $SourceServers) {
    Write-Host ""
    Write-Host "=== Server: $SourceServer ===" -ForegroundColor Yellow
    Write-Log "=== Verarbeite Server: $SourceServer ===" "INFO"
    
    $OutputFileDrivers = Join-Path $OutputDir "2.4-Export-$SourceServer-Drivers.xml"
    
    # Prüfe ob Server erreichbar ist
    Write-Host "Prüfe Verbindung zu $SourceServer..." -ForegroundColor Cyan
    Write-Log "Prüfe Verbindung zu $SourceServer..." "INFO"
    
    if (-not (Test-Connection -ComputerName $SourceServer -Count 1 -Quiet)) {
        Write-Log "Server $SourceServer ist nicht erreichbar!" "ERROR"
        Write-Host "  [FEHLER] Server $SourceServer ist nicht erreichbar!" -ForegroundColor Red
        $failedServers += $SourceServer
        continue
    }
    Write-Host "  [OK] Server ist erreichbar" -ForegroundColor Green
    Write-Log "Server $SourceServer ist erreichbar" "SUCCESS"
    
    # Exportiere Druckertreiber
    Write-Host "Exportiere Druckertreiber..." -ForegroundColor Cyan
    Write-Log "Exportiere Druckertreiber von $SourceServer..." "INFO"
    
    try {
        $drivers = Get-PrinterDriver -ComputerName $SourceServer -ErrorAction Stop
        Write-Host "  Gefundene Treiber: $($drivers.Count)" -ForegroundColor Green
        Write-Log "Gefundene Treiber auf $SourceServer: $($drivers.Count)" "INFO"
        
        if ($drivers.Count -eq 0) {
            Write-Log "KEINE Treiber auf $SourceServer gefunden!" "WARNING"
            Write-Host "  [WARNUNG] Keine Treiber gefunden!" -ForegroundColor Yellow
        }
        else {
            # Erstelle Array mit allen Treiber-Informationen
            $driverInfo = @()
            
            foreach ($driver in $drivers) {
                $driverDetails = [PSCustomObject]@{
                    Name = $driver.Name
                    PrinterEnvironment = $driver.PrinterEnvironment
                    MajorVersion = $driver.MajorVersion
                    MinorVersion = $driver.MinorVersion
                    DriverPath = $driver.DriverPath
                    DataFile = $driver.DataFile
                    ConfigFile = $driver.ConfigFile
                    HelpFile = $driver.HelpFile
                    DependentFiles = $driver.DependentFiles
                    Monitor = $driver.Monitor
                    DefaultDatatype = $driver.DefaultDatatype
                    SupportedPlatforms = $driver.SupportedPlatforms
                }
                $driverInfo += $driverDetails
            }
            
            # Exportiere als CliXML
            $driverInfo | Export-Clixml -Path $OutputFileDrivers -Force
            Write-Log "Treiber exportiert: $($drivers.Count)" "SUCCESS"
            Write-Host "  [OK] Treiber exportiert: $($drivers.Count)" -ForegroundColor Green
            
            $fileSize = (Get-Item $OutputFileDrivers).Length / 1KB
            Write-Host "  Datei: $OutputFileDrivers ($([math]::Round($fileSize, 2)) KB)" -ForegroundColor Gray
            Write-Log "Datei gespeichert: $OutputFileDrivers ($([math]::Round($fileSize, 2)) KB)" "INFO"
            
            # Zeige Liste der Treiber
            Write-Host ""
            Write-Host "  Exportierte Treiber:" -ForegroundColor Cyan
            foreach ($driver in $drivers) {
                Write-Host "    - $($driver.Name) ($($driver.PrinterEnvironment))" -ForegroundColor Gray
                Write-Log "  Treiber: $($driver.Name) ($($driver.PrinterEnvironment))" "INFO"
            }
            
            $totalDrivers += $drivers.Count
            $totalServers++
        }
    }
    catch {
        Write-Log "FEHLER beim Exportieren der Treiber von $SourceServer: $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        $failedServers += $SourceServer
    }
}

Write-Host ""
Write-Host "=== EXPORT ABGESCHLOSSEN ===" -ForegroundColor Cyan
Write-Log "=== Export Druckertreiber abgeschlossen ===" "INFO"
Write-Host ""

Write-Host "Zusammenfassung:" -ForegroundColor Yellow
Write-Host "  - Erfolgreich verarbeitete Server: $totalServers" -ForegroundColor $(if ($totalServers -eq $SourceServers.Count) { "Green" } else { "Yellow" })
Write-Host "  - Gesamt exportierte Treiber: $totalDrivers" -ForegroundColor Green

if ($failedServers.Count -gt 0) {
    Write-Host "  - Fehlgeschlagene Server: $($failedServers -join ', ')" -ForegroundColor Red
    Write-Log "Fehlgeschlagene Server: $($failedServers -join ', ')" "WARNING"
}

Write-Host ""
Write-Host "Exportierte Dateien:" -ForegroundColor Cyan
foreach ($server in $SourceServers) {
    $file = Join-Path $OutputDir "2.4-Export-$server-Drivers.xml"
    if (Test-Path $file) {
        Write-Host "  - $file" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Log "Log-Datei: $LogFile" "INFO"
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

