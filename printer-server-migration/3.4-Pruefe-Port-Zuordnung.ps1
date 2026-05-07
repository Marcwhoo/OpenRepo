# ==================================================================
# Phase 3: PrÃ¼fe Zuordnung-Port-Namen.csv auf Fehler
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$PortZuordnungCSV = Join-Path $OutputDir "3.3-Zuordnung-Port-Namen.csv"

# PrÃ¼fe ob CSV-Datei existiert
if (-not (Test-Path $PortZuordnungCSV)) {
    Write-Host "FEHLER: CSV-Datei nicht gefunden: $PortZuordnungCSV" -ForegroundColor Red
    exit 1
}

$csv = Import-Csv -Path $PortZuordnungCSV -Delimiter ";" -Encoding UTF8

$errors = @()
$warnings = @()

foreach ($row in $csv) {
    # PrÃ¼fe 1: NewPortName muss mit IPAddress beginnen (wenn Status OK und IP vorhanden)
    if ($row.Status -eq "OK" -and $row.IPAddress -ne "" -and $row.NewPortName -ne "") {
        if (-not $row.NewPortName.StartsWith($row.IPAddress)) {
            $errors += "Zeile $($csv.IndexOf($row) + 2): NewPortName beginnt nicht mit IPAddress - OldPortName: $($row.OldPortName), IPAddress: $($row.IPAddress), NewPortName: $($row.NewPortName)"
        }
    }
    
    # PrÃ¼fe 2: Formatfehler in NewPrinterName (doppeltes BRO)
    if ($row.NewPrinterName -match "BRO-.*-BRO") {
        $warnings += "Zeile $($csv.IndexOf($row) + 2): NewPrinterName enthÃ¤lt doppeltes BRO - $($row.NewPrinterName)"
    }
    
    # PrÃ¼fe 3: Status und Action mÃ¼ssen konsistent sein
    if ($row.Status -eq "OK" -and $row.Action -ne "UMBENENNEN") {
        $errors += "Zeile $($csv.IndexOf($row) + 2): Status OK aber Action ist nicht UMBENENNEN - Action: $($row.Action)"
    }
    if ($row.Status -eq "NICHT_VERWENDET" -and $row.Action -ne "AUS_XML_ENTFERNEN") {
        $errors += "Zeile $($csv.IndexOf($row) + 2): Status NICHT_VERWENDET aber Action ist nicht AUS_XML_ENTFERNEN - Action: $($row.Action)"
    }
}

Write-Host "=== PrÃ¼fung abgeschlossen ===" -ForegroundColor Cyan
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "FEHLER gefunden: $($errors.Count)" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  $err" -ForegroundColor Red
    }
} else {
    Write-Host "Keine Fehler gefunden!" -ForegroundColor Green
}

Write-Host ""

if ($warnings.Count -gt 0) {
    Write-Host "WARNUNGEN: $($warnings.Count)" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  $warning" -ForegroundColor Yellow
    }
} else {
    Write-Host "Keine Warnungen!" -ForegroundColor Green
}

