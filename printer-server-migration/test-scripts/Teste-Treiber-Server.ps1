# ==================================================================
# Test-Script: Prüft ob alle Druckertreiber installiert sind
# ==================================================================
# 
# Dieses Script prüft für alle Drucker auf dem Server, ob die
# benötigten Treiber installiert sind.
#
# Es erstellt eine Übersicht:
# - Welche Treiber benötigt werden
# - Welche Treiber bereits installiert sind
# - Welche Treiber fehlen
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV = $false
)

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = $ScriptDir
$LogDir = Join-Path $OutputDir "..\Logs"
$LogFile = Join-Path $LogDir "Test-Printer-Drivers-Check_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Log-Verzeichnis falls nicht vorhanden
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Logging-Funktion
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Host ""
Write-Host "=== PRÜFUNG DER DRUCKERTREIBER ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

Write-Log "=== Prüfung der Druckertreiber gestartet ===" "INFO"
Write-Log "Zielserver: $ComputerName" "INFO"

# SCHRITT 1: Alle Drucker vom Server abrufen
Write-Host "=== SCHRITT 1: Drucker abrufen ===" -ForegroundColor Cyan
Write-Log "Rufe alle Drucker vom Server ab..." "INFO"

try {
    $printers = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
    Write-Log "Gefunden: $($printers.Count) Drucker" "SUCCESS"
    Write-Host "  [OK] Gefunden: $($printers.Count) Drucker" -ForegroundColor Green
} catch {
    Write-Log "FEHLER beim Abrufen der Drucker: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($printers.Count -eq 0) {
    Write-Log "KEINE Drucker gefunden!" "WARNING"
    Write-Host "  [WARNUNG] Keine Drucker gefunden!" -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# SCHRITT 2: Alle installierten Treiber abrufen
Write-Host "=== SCHRITT 2: Installierte Treiber abrufen ===" -ForegroundColor Cyan
Write-Log "Rufe alle installierten Treiber ab..." "INFO"

try {
    $installedDrivers = Get-PrinterDriver -ComputerName $ComputerName -ErrorAction Stop
    Write-Log "Gefunden: $($installedDrivers.Count) installierte Treiber" "SUCCESS"
    Write-Host "  [OK] Gefunden: $($installedDrivers.Count) installierte Treiber" -ForegroundColor Green
    
    # Erstelle Hashtable für schnelle Suche
    $driverHash = @{}
    foreach ($driver in $installedDrivers) {
        $driverHash[$driver.Name] = $driver
    }
} catch {
    Write-Log "FEHLER beim Abrufen der Treiber: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# SCHRITT 3: Für jeden Drucker den Treiber prüfen
Write-Host "=== SCHRITT 3: Treiber-Prüfung für jeden Drucker ===" -ForegroundColor Cyan
Write-Host ""

$printerResults = @()
$requiredDrivers = @{}
$missingDrivers = @{}

foreach ($printer in $printers) {
    $printerName = $printer.Name
    $driverName = $printer.DriverName
    
    if ([string]::IsNullOrWhiteSpace($driverName)) {
        Write-Log "  WARNUNG: Drucker '$printerName' hat keinen Treiber zugewiesen!" "WARNING"
        Write-Host "  [WARNUNG] $printerName - Kein Treiber zugewiesen" -ForegroundColor Yellow
        
        $printerResults += [PSCustomObject]@{
            PrinterName = $printerName
            DriverName = "(kein Treiber)"
            DriverInstalled = $false
            Status = "KEIN_TREIBER"
            PortName = if ($printer.PortName) { $printer.PortName } else { "" }
            Shared = $printer.Shared
        }
        continue
    }
    
    # Prüfe ob Treiber installiert ist
    $isInstalled = $driverHash.ContainsKey($driverName)
    
    # Sammle benötigte Treiber
    if (-not $requiredDrivers.ContainsKey($driverName)) {
        $requiredDrivers[$driverName] = @{
            DriverName = $driverName
            IsInstalled = $isInstalled
            PrinterCount = 0
            Printers = @()
        }
    }
    
    $requiredDrivers[$driverName].PrinterCount++
    $requiredDrivers[$driverName].Printers += $printerName
    
    if (-not $isInstalled) {
        if (-not $missingDrivers.ContainsKey($driverName)) {
            $missingDrivers[$driverName] = @{
                DriverName = $driverName
                PrinterCount = 0
                Printers = @()
            }
        }
        $missingDrivers[$driverName].PrinterCount++
        $missingDrivers[$driverName].Printers += $printerName
    }
    
    $status = if ($isInstalled) { "OK" } else { "FEHLT" }
    $statusColor = if ($isInstalled) { "Green" } else { "Red" }
    
    Write-Host "  [$status] $printerName" -ForegroundColor $statusColor
    Write-Host "           Treiber: $driverName" -ForegroundColor Gray
    
    if (-not $isInstalled) {
        Write-Log "  FEHLT: Drucker '$printerName' benötigt Treiber '$driverName' (nicht installiert)" "ERROR"
    } else {
        Write-Log "  OK: Drucker '$printerName' - Treiber '$driverName' ist installiert" "INFO"
    }
    
    $printerResults += [PSCustomObject]@{
        PrinterName = $printerName
        DriverName = $driverName
        DriverInstalled = $isInstalled
        Status = $status
        PortName = if ($printer.PortName) { $printer.PortName } else { "" }
        Shared = $printer.Shared
    }
}

Write-Host ""

# SCHRITT 4: Zusammenfassung
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

$totalPrinters = $printers.Count
$printersWithDriver = ($printerResults | Where-Object { $_.DriverInstalled -eq $true }).Count
$printersWithoutDriver = ($printerResults | Where-Object { $_.DriverInstalled -eq $false -and $_.Status -ne "KEIN_TREIBER" }).Count
$printersNoDriver = ($printerResults | Where-Object { $_.Status -eq "KEIN_TREIBER" }).Count

Write-Host "Drucker-Statistik:" -ForegroundColor Yellow
Write-Host "  Gesamt: $totalPrinters" -ForegroundColor White
Write-Host "  Mit installiertem Treiber: $printersWithDriver" -ForegroundColor Green
Write-Host "  Mit fehlendem Treiber: $printersWithoutDriver" -ForegroundColor Red
Write-Host "  Ohne zugewiesenen Treiber: $printersNoDriver" -ForegroundColor Yellow
Write-Host ""

Write-Log "Zusammenfassung: $totalPrinters Drucker gesamt, $printersWithDriver mit Treiber, $printersWithoutDriver mit fehlendem Treiber, $printersNoDriver ohne Treiber" "INFO"

# Treiber-Statistik
Write-Host "Treiber-Statistik:" -ForegroundColor Yellow
Write-Host "  Benötigte Treiber: $($requiredDrivers.Count)" -ForegroundColor White
Write-Host "  Installierte Treiber: $(($requiredDrivers.Values | Where-Object { $_.IsInstalled }).Count)" -ForegroundColor Green
Write-Host "  Fehlende Treiber: $($missingDrivers.Count)" -ForegroundColor Red
Write-Host ""

Write-Log "Treiber-Statistik: $($requiredDrivers.Count) benötigt, $(($requiredDrivers.Values | Where-Object { $_.IsInstalled }).Count) installiert, $($missingDrivers.Count) fehlen" "INFO"

# Liste der fehlenden Treiber
if ($missingDrivers.Count -gt 0) {
    Write-Host "=== FEHLENDE TREIBER ===" -ForegroundColor Red
    Write-Host ""
    
    foreach ($driverName in ($missingDrivers.Keys | Sort-Object)) {
        $driverInfo = $missingDrivers[$driverName]
        Write-Host "  Treiber: $driverName" -ForegroundColor Red
        Write-Host "    Wird benötigt von $($driverInfo.PrinterCount) Drucker(n):" -ForegroundColor Yellow
        
        foreach ($printerName in $driverInfo.Printers) {
            Write-Host "      - $printerName" -ForegroundColor Gray
        }
        Write-Host ""
        
        Write-Log "FEHLENDER TREIBER: $driverName (benötigt von $($driverInfo.PrinterCount) Druckern)" "ERROR"
    }
} else {
    Write-Host "=== ALLE TREIBER INSTALLIERT ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "  [OK] Alle benötigten Treiber sind installiert!" -ForegroundColor Green
    Write-Log "Alle benötigten Treiber sind installiert" "SUCCESS"
}

# Liste aller benötigten Treiber (sortiert)
Write-Host ""
Write-Host "=== ALLE BENÖTIGTEN TREIBER ===" -ForegroundColor Cyan
Write-Host ""

$sortedDrivers = $requiredDrivers.Values | Sort-Object DriverName
foreach ($driverInfo in $sortedDrivers) {
    $status = if ($driverInfo.IsInstalled) { "[OK]" } else { "[FEHLT]" }
    $color = if ($driverInfo.IsInstalled) { "Green" } else { "Red" }
    
    Write-Host "  $status $($driverInfo.DriverName)" -ForegroundColor $color
    Write-Host "      Verwendet von $($driverInfo.PrinterCount) Drucker(n)" -ForegroundColor Gray
    Write-Host ""
}

# Export zu CSV (optional)
if ($ExportCSV) {
    $csvFile = Join-Path $LogDir "Test-Printer-Drivers-Check_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    try {
        $printerResults | Export-Csv -Path $csvFile -Encoding UTF8 -NoTypeInformation -Delimiter ";"
        Write-Host "=== CSV-EXPORT ===" -ForegroundColor Cyan
        Write-Host "  [OK] Ergebnisse exportiert: $csvFile" -ForegroundColor Green
        Write-Log "CSV-Export erstellt: $csvFile" "SUCCESS"
    } catch {
        Write-Host "  [FEHLER] CSV-Export fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "FEHLER beim CSV-Export: $($_.Exception.Message)" "ERROR"
    }
}

Write-Host ""
Write-Host "=== PRÜFUNG ABGESCHLOSSEN ===" -ForegroundColor Cyan
Write-Log "=== Prüfung abgeschlossen ===" "INFO"
Write-Host ""