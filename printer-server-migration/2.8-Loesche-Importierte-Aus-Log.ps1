# ==================================================================
# Phase 2.8: Löscht importierte Drucker und Ports basierend auf Log-File
# Extrahiert die Namen aus dem Log-File und löscht sie ohne -Force
# ==================================================================

$ErrorActionPreference = "Continue"

$LogFile = "\\<PRINT-SERVER-1>-01\c$\Windows\System32\Logs\2.6-Importiere-nur-Treiber_2026-01-06_105659.log"
$OutputLog = "(Join-Path $PSScriptRoot "Logs")\2.8-Loesche-Importierte-Aus-Log_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Log-Verzeichnis
$LogDir = "(Join-Path $PSScriptRoot "Logs")"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $OutputLog -Value $logMessage -Encoding UTF8
}

Write-Host ""
Write-Host "=== LÖSCHE IMPORTIERTE DRUCKER UND PORTS AUS LOG ===" -ForegroundColor Cyan
Write-Host ""

# Lese Log-File
if (-not (Test-Path $LogFile)) {
    Write-Log "FEHLER: Log-File nicht gefunden: $LogFile" "ERROR"
    Write-Host "  [FEHLER] Log-File nicht gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "Lese Log-File: $LogFile" -ForegroundColor Cyan
try {
    $logContent = Get-Content $LogFile -Encoding UTF8 -ErrorAction Stop
    Write-Host "  [OK] $($logContent.Count) Zeilen gelesen" -ForegroundColor Green
} catch {
    # Versuche mit Default-Encoding
    $logContent = Get-Content $LogFile -ErrorAction Stop
    Write-Host "  [OK] $($logContent.Count) Zeilen gelesen (Default-Encoding)" -ForegroundColor Green
}

# Extrahiere Drucker-Namen
$printersToDelete = @()
$portsToDelete = @()

foreach ($line in $logContent) {
    # Drucker: Suche nach "Drucker" und "FEHLER" in der Zeile
    if ($line -like "*Drucker*" -and $line -like "*FEHLER*") {
        # Extrahiere den Namen zwischen "Drucker " und " :"
        $startIndex = $line.IndexOf("Drucker ")
        if ($startIndex -ge 0) {
            $startIndex += 8
            $endIndex = $line.IndexOf(" :", $startIndex)
            if ($endIndex -gt $startIndex) {
                $printerName = $line.Substring($startIndex, $endIndex - $startIndex).Trim()
                if ($printerName -and $printerName -notin $printersToDelete) {
                    $printersToDelete += $printerName
                }
            }
        }
    }
    # Port: Suche nach "Port" und "FEHLER" in der Zeile
    elseif ($line -like "*Port*" -and $line -like "*FEHLER*" -and $line -notlike "*Drucker*") {
        # Extrahiere den Namen zwischen "Port " und " :"
        $startIndex = $line.IndexOf("Port ")
        if ($startIndex -ge 0) {
            $startIndex += 5
            $endIndex = $line.IndexOf(" :", $startIndex)
            if ($endIndex -gt $startIndex) {
                $portName = $line.Substring($startIndex, $endIndex - $startIndex).Trim()
                # Überspringe WSD-Ports und Standard-Ports
                if ($portName -and $portName -notlike "WSD:*" -and $portName -notlike "FILE:*" -and $portName -notlike "PORTPROMPT:*" -and $portName -notin $portsToDelete) {
                    $portsToDelete += $portName
                }
            }
        }
    }
}

Write-Host "Gefundene Drucker zum Löschen: $($printersToDelete.Count)" -ForegroundColor Yellow
Write-Host "Gefundene Ports zum Löschen: $($portsToDelete.Count)" -ForegroundColor Yellow
Write-Host ""

Write-Log "Gefundene Drucker: $($printersToDelete.Count)" "INFO"
Write-Log "Gefundene Ports: $($portsToDelete.Count)" "INFO"

if ($printersToDelete.Count -eq 0 -and $portsToDelete.Count -eq 0) {
    Write-Host "Keine Drucker oder Ports zum Löschen gefunden." -ForegroundColor Yellow
    exit 0
}

# Bestätigung
Write-Host "WARNUNG: Dieses Script wird löschen:" -ForegroundColor Yellow
Write-Host "  - $($printersToDelete.Count) Drucker" -ForegroundColor Yellow
Write-Host "  - $($portsToDelete.Count) Ports" -ForegroundColor Yellow
Write-Host ""
$confirmation = Read-Host "Möchten Sie fortfahren? (JA zum Fortfahren)"
if ($confirmation -ne "JA") {
    Write-Log "Abgebrochen durch Benutzer" "INFO"
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== LÖSCHE DRUCKER ===" -ForegroundColor Cyan
Write-Host ""

$deletedPrinters = 0
$failedPrinters = 0

foreach ($printerName in $printersToDelete) {
    try {
        Remove-Printer -Name $printerName -ErrorAction Stop
        Write-Log "Drucker gelöscht: $printerName" "SUCCESS"
        Write-Host "  [OK] Drucker gelöscht: $printerName" -ForegroundColor Green
        $deletedPrinters++
    } catch {
        Write-Log "FEHLER beim Löschen von Drucker $printerName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] Drucker $printerName : $($_.Exception.Message)" -ForegroundColor Red
        $failedPrinters++
    }
}

Write-Host ""
Write-Host "=== LÖSCHE PORTS ===" -ForegroundColor Cyan
Write-Host ""

$deletedPorts = 0
$failedPorts = 0

foreach ($portName in $portsToDelete) {
    try {
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "Port gelöscht: $portName" "SUCCESS"
        Write-Host "  [OK] Port gelöscht: $portName" -ForegroundColor Green
        $deletedPorts++
    } catch {
        Write-Log "FEHLER beim Löschen von Port $portName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] Port $portName : $($_.Exception.Message)" -ForegroundColor Red
        $failedPorts++
    }
}

Write-Host ""
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host "Gelöschte Drucker: $deletedPrinters / $($printersToDelete.Count)" -ForegroundColor $(if ($deletedPrinters -eq $printersToDelete.Count) { "Green" } else { "Yellow" })
Write-Host "Fehlgeschlagene Drucker: $failedPrinters" -ForegroundColor $(if ($failedPrinters -eq 0) { "Green" } else { "Red" })
Write-Host "Gelöschte Ports: $deletedPorts / $($portsToDelete.Count)" -ForegroundColor $(if ($deletedPorts -eq $portsToDelete.Count) { "Green" } else { "Yellow" })
Write-Host "Fehlgeschlagene Ports: $failedPorts" -ForegroundColor $(if ($failedPorts -eq 0) { "Green" } else { "Red" })
Write-Host ""

Write-Log "Zusammenfassung: $deletedPrinters/$($printersToDelete.Count) Drucker gelöscht, $deletedPorts/$($portsToDelete.Count) Ports gelöscht" "INFO"
Write-Host "Log-Datei: $OutputLog" -ForegroundColor Gray
Write-Host ""

