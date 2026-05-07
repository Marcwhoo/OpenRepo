# Test: Einzelner Drucker komplett - Port, Drucker, Share-Name
param(
    [string]$ComputerName = "<PRINT-SERVER-1>-01"
)

$ErrorActionPreference = "Stop"

Write-Host "=== TEST: Einzelner Drucker komplett ===" -ForegroundColor Cyan
Write-Host ""

# Test-Daten
$testPrinterName = "<LOCATION>-<MODEL>-<AREA>-SW"
$testIP = "<IP-ADDRESS>"
$testPortName = "<IP-ADDRESS> <LOCATION>-<AREA>"
$testDriver = "Universal Print Class Driver"

Write-Host "Test-Daten:" -ForegroundColor Yellow
Write-Host "  Drucker-Name: $testPrinterName"
Write-Host "  Port-Name: $testPortName"
Write-Host "  IP-Adresse: $testIP"
Write-Host "  Treiber: $testDriver"
Write-Host ""

# Lade Funktionen aus Import-Script
$importScript = Join-Path $PSScriptRoot '5.1-Importiere-Druckkonfiguration.ps1'
. $importScript -ErrorAction SilentlyContinue

# Funktion zum Bereinigen von Share-Namen (falls nicht geladen)
if (-not (Get-Command Remove-InvalidShareCharacters -ErrorAction SilentlyContinue)) {
    function Remove-InvalidShareCharacters {
        param([string]$ShareName)
        if ([string]::IsNullOrWhiteSpace($ShareName)) { return $ShareName }
        $cleaned = $ShareName -replace '\s+', '_'
        $cleaned = $cleaned -replace '\.', '_'
        $cleaned = $cleaned -replace '-', '_'
        $cleaned = $cleaned -replace '[^a-zA-Z0-9_]', '_'
        $cleaned = $cleaned -replace '_+', '_'
        $cleaned = $cleaned.Trim('_')
        if ([string]::IsNullOrWhiteSpace($cleaned)) { $cleaned = "Printer_Share" }
        if ($cleaned.Length -gt 80) {
            $cleaned = $cleaned.Substring(0, 80)
            $cleaned = $cleaned.Trim('_')
        }
        return $cleaned
    }
}

# SCHRITT 1: Bereinige und bereite Share-Name vor
Write-Host "=== SCHRITT 1: Share-Name bereinigen ===" -ForegroundColor Cyan
$shareNameToUse = Remove-InvalidShareCharacters -ShareName $testPrinterName
Write-Host "Original: $testPrinterName"
Write-Host "Bereinigt: $shareNameToUse"
Write-Host "Länge: $($shareNameToUse.Length)"
Write-Host ""

# SCHRITT 2: Port erstellen
Write-Host "=== SCHRITT 2: Port erstellen ===" -ForegroundColor Cyan
$existingPort = Get-PrinterPort -ComputerName $ComputerName -Name $testPortName -ErrorAction SilentlyContinue
if ($existingPort) {
    Write-Host "  [INFO] Port existiert bereits: $testPortName" -ForegroundColor Yellow
    Remove-PrinterPort -ComputerName $ComputerName -Name $testPortName -ErrorAction Stop
    Write-Host "  [OK] Port gelöscht" -ForegroundColor Green
}

try {
    Add-PrinterPort -Name $testPortName -ComputerName $ComputerName -PrinterHostAddress $testIP -PortNumber 9100 -ErrorAction Stop
    Write-Host "  [OK] Port erstellt: $testPortName" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Port konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# SCHRITT 3: Prüfe Treiber
Write-Host "=== SCHRITT 3: Treiber prüfen ===" -ForegroundColor Cyan
$driver = Get-PrinterDriver -ComputerName $ComputerName -Name $testDriver -ErrorAction SilentlyContinue
if (-not $driver) {
    Write-Host "  [FEHLER] Treiber '$testDriver' ist nicht installiert!" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Treiber gefunden: $testDriver" -ForegroundColor Green
Write-Host ""

# SCHRITT 4: Drucker löschen falls vorhanden
Write-Host "=== SCHRITT 4: Alten Drucker entfernen ===" -ForegroundColor Cyan
$existingPrinter = Get-Printer -ComputerName $ComputerName -Name $testPrinterName -ErrorAction SilentlyContinue
if ($existingPrinter) {
    Write-Host "  [INFO] Drucker existiert bereits, lösche..." -ForegroundColor Yellow
    Remove-Printer -ComputerName $ComputerName -Name $testPrinterName -ErrorAction Stop
    Write-Host "  [OK] Drucker gelöscht" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Kein alter Drucker vorhanden" -ForegroundColor Gray
}
Write-Host ""

# SCHRITT 5: Drucker erstellen
Write-Host "=== SCHRITT 5: Drucker erstellen ===" -ForegroundColor Cyan
try {
    Add-Printer -Name $testPrinterName -ComputerName $ComputerName -DriverName $testDriver -PortName $testPortName -ErrorAction Stop
    Write-Host "  [OK] Drucker erstellt: $testPrinterName" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Drucker konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# SCHRITT 6: Drucker teilen mit bereinigtem Share-Name
Write-Host "=== SCHRITT 6: Drucker teilen ===" -ForegroundColor Cyan
Write-Host "  Verwende Share-Name: $shareNameToUse" -ForegroundColor Yellow
Write-Host ""

try {
    Set-Printer -Name $testPrinterName -ComputerName $ComputerName -Shared $true -ShareName $shareNameToUse -ErrorAction Stop
    Write-Host "  [OK] Drucker geteilt: $testPrinterName" -ForegroundColor Green
    Write-Host "  [OK] Share-Name: $shareNameToUse" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Drucker konnte nicht geteilt werden: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fehler-Details: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Versuche ohne ShareName..." -ForegroundColor Yellow
    try {
        Set-Printer -Name $testPrinterName -ComputerName $ComputerName -Shared $true -ErrorAction Stop
        Write-Host "  [OK] Drucker geteilt (ohne ShareName)" -ForegroundColor Green
    } catch {
        Write-Host "  [FEHLER] Auch ohne ShareName fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# SCHRITT 7: Verifikation
Write-Host "=== SCHRITT 7: Verifikation ===" -ForegroundColor Cyan
$importedPrinter = Get-Printer -ComputerName $ComputerName -Name $testPrinterName -ErrorAction SilentlyContinue
if ($importedPrinter) {
    Write-Host "  [OK] Drucker gefunden: $($importedPrinter.Name)" -ForegroundColor Green
    Write-Host "  Shared: $($importedPrinter.Shared)" -ForegroundColor $(if ($importedPrinter.Shared) { "Green" } else { "Red" })
    Write-Host "  ShareName: $($importedPrinter.ShareName)" -ForegroundColor Green
    Write-Host "  PortName: $($importedPrinter.PortName)" -ForegroundColor Green
    Write-Host "  DriverName: $($importedPrinter.DriverName)" -ForegroundColor Green
    
    if ($importedPrinter.Shared -eq $true -and $importedPrinter.ShareName -eq $shareNameToUse) {
        Write-Host ""
        Write-Host "=== TEST ERFOLGREICH ===" -ForegroundColor Green
        Write-Host "Der Drucker wurde erfolgreich importiert und geteilt!" -ForegroundColor Green
        Write-Host "Share-Name: $shareNameToUse" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "=== TEST TEILWEISE ERFOLGREICH ===" -ForegroundColor Yellow
        if ($importedPrinter.Shared -ne $true) {
            Write-Host "Drucker wurde nicht geteilt (Shared = $($importedPrinter.Shared))" -ForegroundColor Yellow
        }
        if ($importedPrinter.ShareName -ne $shareNameToUse) {
            Write-Host "Share-Name stimmt nicht überein:" -ForegroundColor Yellow
            Write-Host "  Erwartet: $shareNameToUse" -ForegroundColor Yellow
            Write-Host "  Tatsächlich: $($importedPrinter.ShareName)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [FEHLER] Drucker wurde nicht gefunden!" -ForegroundColor Red
    exit 1
}

