# Test-Script: Import eines einzelnen Druckers
# Testet ob Port-Erstellung und Drucker-Import mit Share-Name-Bereinigung funktioniert

param(
    [string]$ComputerName = "<PRINT-SERVER-1>-01"
)

$ErrorActionPreference = "Stop"

# Test-Drucker aus XML laden
$testFile = Get-ChildItem -Path "$PSScriptRoot" -Filter "4.1-Import-<PRINT-SERVER-1>-Printers.xml" | Select-Object -First 1
if (-not $testFile) {
    Write-Host "FEHLER: Keine Drucker-XML-Datei gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "=== TEST: Einzelner Drucker-Import ===" -ForegroundColor Cyan
Write-Host "Lade Test-Drucker aus: $($testFile.Name)" -ForegroundColor Yellow
Write-Host ""

# Lade Drucker
$printers = Import-Clixml $testFile.FullName
$testPrinter = $printers | Where-Object { 
    $_.Name -notlike "Microsoft*" -and 
    $_.PortName -match "^\d+\.\d+\.\d+\.\d+" 
} | Select-Object -First 1

if (-not $testPrinter) {
    Write-Host "FEHLER: Kein geeigneter Test-Drucker gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "Test-Drucker:" -ForegroundColor Green
Write-Host "  Name: $($testPrinter.Name)"
Write-Host "  PortName: $($testPrinter.PortName)"
Write-Host "  DriverName: $($testPrinter.DriverName)"
Write-Host "  Shared: $($testPrinter.Shared)"
Write-Host ""

# Lade Funktionen aus Import-Script
$importScript = "$PSScriptRoot\5.1-Importiere-Druckkonfiguration.ps1"
. $importScript -ErrorAction SilentlyContinue

# Funktion zum Bereinigen von Share-Namen (falls nicht geladen)
if (-not (Get-Command Remove-InvalidShareCharacters -ErrorAction SilentlyContinue)) {
    function Remove-InvalidShareCharacters {
        param([string]$ShareName)
        if ([string]::IsNullOrWhiteSpace($ShareName)) { return $ShareName }
        $cleaned = $ShareName -replace '\s+', '_'
        $cleaned = $cleaned -replace '[/\\,<>:"|?*]', ''
        $cleaned = $cleaned -replace '_+', '_'
        $cleaned = $cleaned.Trim('_')
        if ($cleaned.Length -gt 80) {
            $cleaned = $cleaned.Substring(0, 80)
            $cleaned = $cleaned.Trim('_')
        }
        return $cleaned
    }
}

# Funktion zum Bereinigen von Port-Namen (falls nicht geladen)
if (-not (Get-Command Remove-InvalidPortCharacters -ErrorAction SilentlyContinue)) {
    function Remove-InvalidPortCharacters {
        param([string]$PortName)
        if ([string]::IsNullOrWhiteSpace($PortName)) { return $PortName }
        $cleaned = $PortName -replace '[()<>:"/\\|?*]', ''
        $cleaned = $cleaned -replace '\s+', ' '
        $cleaned = $cleaned.Trim()
        if ($cleaned -match '^(\d+\.\d+\.\d+\.\d+)\s+(.+)$') {
            $ipAddress = $matches[1]
            $printerName = $matches[2]
            $printerName = $printerName -replace '-(BRO|KYO|KON|CAN|HP)(-[A-Z0-9]+){1,3}?(?=-[A-Z][a-z])', ''
            $printerName = $printerName -replace '--+', '-'
            $printerName = $printerName.Trim('-')
            $printerName = $printerName -replace '-(SW|COL)$', ''
            $printerName = $printerName.Trim('-')
            $cleaned = "$ipAddress $printerName"
            if ($cleaned.Length -gt 60) {
                $cleaned = $cleaned.Substring(0, 60)
                $cleaned = $cleaned.Trim()
            }
        }
        return $cleaned
    }
}

# SCHRITT 1: Port erstellen
Write-Host "=== SCHRITT 1: Port erstellen ===" -ForegroundColor Cyan
$originalPortName = $testPrinter.PortName
$portName = Remove-InvalidPortCharacters -PortName $originalPortName

# Extrahiere IP-Adresse
if ($portName -match '^(\d+\.\d+\.\d+\.\d+)') {
    $ipAddress = $matches[1]
} else {
    Write-Host "FEHLER: Keine IP-Adresse im Port-Namen gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "Original Port-Name: $originalPortName"
Write-Host "Bereinigter Port-Name: $portName"
Write-Host "IP-Adresse: $ipAddress"
Write-Host ""

# Prüfe ob Port bereits existiert
$existingPort = Get-PrinterPort -ComputerName $ComputerName -Name $portName -ErrorAction SilentlyContinue
if ($existingPort) {
    Write-Host "  [INFO] Port existiert bereits: $portName" -ForegroundColor Yellow
} else {
    try {
        Add-PrinterPort -Name $portName -ComputerName $ComputerName -PrinterHostAddress $ipAddress -PortNumber 9100 -ErrorAction Stop
        Write-Host "  [OK] Port erstellt: $portName" -ForegroundColor Green
    } catch {
        Write-Host "  [FEHLER] Port konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# SCHRITT 2: Drucker erstellen
Write-Host "=== SCHRITT 2: Drucker erstellen ===" -ForegroundColor Cyan
$printerName = $testPrinter.Name
$driverName = $testPrinter.DriverName

Write-Host "Drucker-Name: $printerName"
Write-Host "Treiber: $driverName"
Write-Host "Port: $portName"
Write-Host ""

# Prüfe ob Treiber existiert
$driver = Get-PrinterDriver -ComputerName $ComputerName -Name $driverName -ErrorAction SilentlyContinue
if (-not $driver) {
    Write-Host "  [FEHLER] Treiber '$driverName' ist nicht installiert!" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Treiber gefunden: $driverName" -ForegroundColor Green

# Prüfe ob Drucker bereits existiert
$existingPrinter = Get-Printer -ComputerName $ComputerName -Name $printerName -ErrorAction SilentlyContinue
if ($existingPrinter) {
    Write-Host "  [INFO] Drucker existiert bereits, lösche..." -ForegroundColor Yellow
    Remove-Printer -ComputerName $ComputerName -Name $printerName -ErrorAction Stop
    Write-Host "  [OK] Drucker gelöscht" -ForegroundColor Green
}

# Erstelle Drucker
try {
    Add-Printer -Name $printerName -ComputerName $ComputerName -DriverName $driverName -PortName $portName -ErrorAction Stop
    Write-Host "  [OK] Drucker erstellt: $printerName" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Drucker konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# SCHRITT 3: Drucker teilen
Write-Host "=== SCHRITT 3: Drucker teilen ===" -ForegroundColor Cyan

# Bereinige Share-Name
$shareNameToUse = Remove-InvalidShareCharacters -ShareName $printerName
Write-Host "Original Drucker-Name: $printerName"
Write-Host "Bereinigter Share-Name: $shareNameToUse"
Write-Host ""

try {
    Set-Printer -Name $printerName -ComputerName $ComputerName -Shared $true -ShareName $shareNameToUse -ErrorAction Stop
    Write-Host "  [OK] Drucker geteilt: $printerName (Share: $shareNameToUse)" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Drucker konnte nicht geteilt werden: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Versuche ohne ShareName..." -ForegroundColor Yellow
    try {
        Set-Printer -Name $printerName -ComputerName $ComputerName -Shared $true -ErrorAction Stop
        Write-Host "  [OK] Drucker geteilt (ohne ShareName): $printerName" -ForegroundColor Green
    } catch {
        Write-Host "  [FEHLER] Auch ohne ShareName fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# SCHRITT 4: Verifikation
Write-Host "=== SCHRITT 4: Verifikation ===" -ForegroundColor Cyan
$importedPrinter = Get-Printer -ComputerName $ComputerName -Name $printerName -ErrorAction SilentlyContinue
if ($importedPrinter) {
    Write-Host "  [OK] Drucker gefunden: $($importedPrinter.Name)" -ForegroundColor Green
    Write-Host "  Shared: $($importedPrinter.Shared)"
    Write-Host "  ShareName: $($importedPrinter.ShareName)"
    Write-Host "  PortName: $($importedPrinter.PortName)"
    Write-Host "  DriverName: $($importedPrinter.DriverName)"
    
    if ($importedPrinter.Shared -eq $true) {
        Write-Host ""
        Write-Host "=== TEST ERFOLGREICH ===" -ForegroundColor Green
        Write-Host "Der Drucker wurde erfolgreich importiert und geteilt!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "=== TEST TEILWEISE ERFOLGREICH ===" -ForegroundColor Yellow
        Write-Host "Der Drucker wurde importiert, aber nicht geteilt." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [FEHLER] Drucker wurde nicht gefunden!" -ForegroundColor Red
    exit 1
}

