# ==================================================================
# Fallback-Script: Löscht nur die importierten Drucker
# ==================================================================
# 
# WICHTIG: Dieses Script löscht NUR die Drucker, die durch das
#          Import-Script (5.1-Importiere-Druckkonfiguration.ps1) erstellt wurden.
#          Es werden KEINE anderen Drucker gelöscht!
#
# Das Script sucht nach der neuesten Import-Liste im Log-Verzeichnis
# und löscht nur die dort gelisteten Drucker.
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$ImportedPrintersFile = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = $ScriptDir
$LogDir = Join-Path $OutputDir "Logs"
$FallbackLogFile = Join-Path $LogDir "5.2-Fallback-Loesche-Drucker_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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
    Add-Content -Path $FallbackLogFile -Value $logMessage -Encoding UTF8
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Host ""
Write-Host "=== FALLBACK: LÖSCHE IMPORTIERTE DRUCKER ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host ""

if ($WhatIf) {
    Write-Host "WARNUNG: WhatIf-Modus aktiviert - Es werden KEINE Änderungen vorgenommen!" -ForegroundColor Yellow
    Write-Host ""
}

# Prüfe Verbindung zum Server
Write-Log "Prüfe Verbindung zu $ComputerName..." "INFO"
try {
    $connection = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
    if (-not $connection) {
        Write-Log "FEHLER: Keine Verbindung zu $ComputerName möglich" "ERROR"
        exit 1
    }
    Write-Log "Verbindung zu $ComputerName erfolgreich" "SUCCESS"
} catch {
    Write-Log "FEHLER: Verbindung fehlgeschlagen: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Finde Import-Liste
if ([string]::IsNullOrWhiteSpace($ImportedPrintersFile)) {
    Write-Log "Suche nach neuester Import-Liste..." "INFO"
    $importFiles = Get-ChildItem -Path $LogDir -Filter "5.1-Imported-Printers_*.json" | Sort-Object LastWriteTime -Descending
    
    if ($importFiles.Count -eq 0) {
        Write-Log "FEHLER: Keine Import-Liste gefunden in $LogDir" "ERROR"
        Write-Host ""
        Write-Host "Das Script kann keine Import-Liste finden." -ForegroundColor Red
        Write-Host "Bitte geben Sie die Datei explizit mit -ImportedPrintersFile an." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    
    $ImportedPrintersFile = $importFiles[0].FullName
    Write-Log "Gefundene Import-Liste: $($importFiles[0].Name)" "INFO"
}

# Prüfe ob Datei existiert
if (-not (Test-Path $ImportedPrintersFile)) {
    Write-Log "FEHLER: Import-Liste nicht gefunden: $ImportedPrintersFile" "ERROR"
    exit 1
}

# Lade Liste der importierten Drucker
Write-Log "Lade Import-Liste: $ImportedPrintersFile" "INFO"
try {
    $importedPrintersJson = Get-Content -Path $ImportedPrintersFile -Encoding UTF8 -Raw
    $importedPrinters = $importedPrintersJson | ConvertFrom-Json
    
    if ($importedPrinters.Count -eq 0) {
        Write-Log "WARNUNG: Import-Liste ist leer. Keine Drucker zum Löschen." "WARNING"
        exit 0
    }
    
    Write-Log "Gefunden: $($importedPrinters.Count) importierte Drucker in der Liste" "INFO"
} catch {
    Write-Log "FEHLER: Konnte Import-Liste nicht laden: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Zeige Liste der zu löschenden Drucker
Write-Host ""
Write-Host "=== ZU LÖSCHENDE DRUCKER ===" -ForegroundColor Yellow
Write-Host ""
foreach ($printer in $importedPrinters) {
    $printerName = if ($printer.PSObject.Properties.Name -contains "Name") { $printer.Name } else { $printer }
    $printerComputer = if ($printer.PSObject.Properties.Name -contains "ComputerName") { $printer.ComputerName } else { $ComputerName }
    
    Write-Host "  - $printerName (auf $printerComputer)" -ForegroundColor Gray
}
Write-Host ""

# Bestätigung (außer wenn Force gesetzt ist)
if (-not $Force -and -not $WhatIf) {
    Write-Host "WARNUNG: Dieses Script wird die oben gelisteten Drucker löschen!" -ForegroundColor Red
    Write-Host ""
    $confirmation = Read-Host "Sind Sie sicher, dass Sie fortfahren möchten? (JA zum Bestätigen)"
    if ($confirmation -ne "JA") {
        Write-Log "Löschen abgebrochen vom Benutzer" "WARNING"
        Write-Host "Löschen abgebrochen." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# Hole aktuelle Druckerliste vom Server
Write-Log "Hole aktuelle Druckerliste vom Server..." "INFO"
try {
    $currentPrinters = Get-Printer -ComputerName $ComputerName -ErrorAction Stop | Select-Object Name, ComputerName
    Write-Log "Gefunden: $($currentPrinters.Count) Drucker auf dem Server" "INFO"
} catch {
    Write-Log "FEHLER: Konnte Druckerliste nicht abrufen: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Erstelle Mapping der aktuellen Drucker
$currentPrinterMap = @{}
foreach ($printer in $currentPrinters) {
    $key = $printer.ComputerName + '|' + $printer.Name
    $currentPrinterMap[$key] = $printer
}

# Lösche Drucker
Write-Host ""
Write-Host "=== LÖSCHE DRUCKER ===" -ForegroundColor Cyan
Write-Host ""

$deletedCount = 0
$notFoundCount = 0
$errorCount = 0

foreach ($printerInfo in $importedPrinters) {
    $printerName = if ($printerInfo.PSObject.Properties.Name -contains "Name") { $printerInfo.Name } else { $printerInfo }
    $printerComputer = if ($printerInfo.PSObject.Properties.Name -contains "ComputerName") { $printerInfo.ComputerName } else { $ComputerName }
    
    # Prüfe ob Drucker noch existiert
    $key = $printerComputer + '|' + $printerName
    if (-not $currentPrinterMap.ContainsKey($key)) {
        Write-Log "Drucker nicht gefunden (bereits gelöscht?): $printerName auf $printerComputer" "WARNING"
        Write-Host "  [NICHT GEFUNDEN] $printerName" -ForegroundColor Yellow
        $notFoundCount++
        continue
    }
    
    # Lösche Drucker
    try {
        if ($WhatIf) {
            Write-Log "WhatIf: Würde löschen: $printerName auf $printerComputer" "INFO"
            Write-Host "  [WHATIF] Würde löschen: $printerName" -ForegroundColor Cyan
        } else {
            Write-Log "Lösche Drucker: $printerName auf $printerComputer" "INFO"
            Remove-Printer -Name $printerName -ComputerName $printerComputer -ErrorAction Stop
            
            Write-Log "Drucker erfolgreich gelöscht: $printerName" "SUCCESS"
            Write-Host "  [OK] Gelöscht: $printerName" -ForegroundColor Green
        }
        $deletedCount++
        
    } catch {
        $errorMsg = $_.Exception.Message
        $logMsg = "FEHLER beim Loeschen von " + $printerName + ": " + $errorMsg
        Write-Log $logMsg "ERROR"
        Write-Host "  [FEHLER] $printerName - $errorMsg" -ForegroundColor Red
        $errorCount++
    }
}

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host ""
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf-Modus: Keine Änderungen vorgenommen" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Drucker:" -ForegroundColor Yellow
Write-Host "  - Gelöscht: $deletedCount" -ForegroundColor $(if ($deletedCount -gt 0) { "Green" } else { "White" })
Write-Host "  - Nicht gefunden: $notFoundCount" -ForegroundColor $(if ($notFoundCount -gt 0) { "Yellow" } else { "White" })
Write-Host "  - Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "White" })
Write-Host "  - Gesamt in Liste: $($importedPrinters.Count)" -ForegroundColor Gray

Write-Host ""
Write-Log "Fallback abgeschlossen" "INFO"
Write-Log "Log-Datei: $FallbackLogFile" "INFO"

if ($errorCount -eq 0 -and $notFoundCount -eq 0) {
    Write-Host "[OK] Alle importierten Drucker wurden erfolgreich gelöscht" -ForegroundColor Green
} elseif ($errorCount -gt 0) {
    Write-Host "[FEHLER] Einige Drucker konnten nicht gelöscht werden" -ForegroundColor Red
} else {
    Write-Host "[OK] Fallback abgeschlossen" -ForegroundColor Green
}

Write-Host ""

