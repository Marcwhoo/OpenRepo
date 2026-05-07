# ==================================================================
# Phase 2.9: Löscht umgeleitete Drucker und spezielle Ports
# Behandelt: Umgeleitete Drucker, TS-Ports, <NOTEBOOK-HOSTNAME> Ports
# ==================================================================

$ErrorActionPreference = "Continue"

$OutputLog = "(Join-Path $PSScriptRoot "Logs")\2.9-Loesche-Umgeleitete-Drucker-Spezial-Ports_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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
Write-Host "=== LÖSCHE UMGELEITETE DRUCKER UND SPEZIAL-PORTS ===" -ForegroundColor Cyan
Write-Host ""

# Hole alle Drucker
Write-Host "Suche umgeleitete Drucker..." -ForegroundColor Cyan
$allPrinters = Get-Printer
$redirectedPrinters = $allPrinters | Where-Object { $_.Name -like "*(umgeleitet*" }

Write-Host "Gefundene umgeleitete Drucker: $($redirectedPrinters.Count)" -ForegroundColor Yellow
if ($redirectedPrinters.Count -gt 0) {
    foreach ($printer in $redirectedPrinters) {
        Write-Host "  - $($printer.Name)" -ForegroundColor Gray
    }
}

# Hole alle Ports
Write-Host ""
Write-Host "Suche spezielle Ports..." -ForegroundColor Cyan
$allPorts = Get-PrinterPort
$tsPorts = $allPorts | Where-Object { $_.Name -like "TS*" }
$nbPorts = $allPorts | Where-Object { $_.Name -like "NB-*" }
$whPorts = $allPorts | Where-Object { $_.Name -like "WH*" }

Write-Host "Gefundene TS-Ports: $($tsPorts.Count)" -ForegroundColor Yellow
Write-Host "Gefundene NB-Ports: $($nbPorts.Count)" -ForegroundColor Yellow
Write-Host "Gefundene WH-Ports: $($whPorts.Count)" -ForegroundColor Yellow

$totalSpecialPorts = $tsPorts.Count + $nbPorts.Count + $whPorts.Count

if ($redirectedPrinters.Count -eq 0 -and $totalSpecialPorts -eq 0) {
    Write-Host ""
    Write-Host "Keine umgeleiteten Drucker oder speziellen Ports gefunden." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host "Umgeleitete Drucker: $($redirectedPrinters.Count)" -ForegroundColor Yellow
Write-Host "TS-Ports: $($tsPorts.Count)" -ForegroundColor Yellow
Write-Host "NB-Ports: $($nbPorts.Count)" -ForegroundColor Yellow
Write-Host "WH-Ports: $($whPorts.Count)" -ForegroundColor Yellow
Write-Host ""

# Bestätigung
Write-Host "WARNUNG: Dieses Script wird löschen:" -ForegroundColor Yellow
Write-Host "  - $($redirectedPrinters.Count) umgeleitete Drucker" -ForegroundColor Yellow
Write-Host "  - $totalSpecialPorts spezielle Ports" -ForegroundColor Yellow
Write-Host ""
$confirmation = Read-Host "Möchten Sie fortfahren? (JA zum Fortfahren)"
if ($confirmation -ne "JA") {
    Write-Log "Abgebrochen durch Benutzer" "INFO"
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== LÖSCHE UMGELEITETE DRUCKER ===" -ForegroundColor Cyan
Write-Host ""

$deletedPrinters = 0
$failedPrinters = 0

foreach ($printer in $redirectedPrinters) {
    $printerName = $printer.Name
    Write-Host "Verarbeite: $printerName" -ForegroundColor Yellow
    
    try {
        # Versuche zuerst normal zu löschen
        Remove-Printer -Name $printerName -ErrorAction Stop
        Write-Log "Drucker gelöscht: $printerName" "SUCCESS"
        Write-Host "  [OK] Drucker gelöscht" -ForegroundColor Green
        $deletedPrinters++
    } catch {
        # Falls das fehlschlägt, versuche über WMI
        try {
            Write-Host "  Versuche über WMI..." -ForegroundColor Gray
            $printerWMI = Get-WmiObject -Class Win32_Printer -Filter "Name='$($printerName -replace "'", "''")'"
            if ($printerWMI) {
                $printerWMI.Delete()
                Write-Log "Drucker gelöscht über WMI: $printerName" "SUCCESS"
                Write-Host "  [OK] Drucker gelöscht (WMI)" -ForegroundColor Green
                $deletedPrinters++
            } else {
                throw "Drucker nicht über WMI gefunden"
            }
        } catch {
            Write-Log "FEHLER beim Löschen von Drucker $printerName : $($_.Exception.Message)" "ERROR"
            Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
            $failedPrinters++
        }
    }
}

Write-Host ""
Write-Host "=== LÖSCHE TS-PORTS ===" -ForegroundColor Cyan
Write-Host ""

$deletedTSPorts = 0
$failedTSPorts = 0

foreach ($port in $tsPorts) {
    $portName = $port.Name
    Write-Host "Verarbeite: $portName" -ForegroundColor Yellow
    
    try {
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "TS-Port gelöscht: $portName" "SUCCESS"
        Write-Host "  [OK] Port gelöscht" -ForegroundColor Green
        $deletedTSPorts++
    } catch {
        # Versuche über WMI
        try {
            Write-Host "  Versuche über WMI..." -ForegroundColor Gray
            $portWMI = Get-WmiObject -Class Win32_TCPIPPrinterPort -Filter "Name='$($portName -replace "'", "''")'"
            if ($portWMI) {
                $portWMI.Delete()
                Write-Log "TS-Port gelöscht über WMI: $portName" "SUCCESS"
                Write-Host "  [OK] Port gelöscht (WMI)" -ForegroundColor Green
                $deletedTSPorts++
            } else {
                throw "Port nicht über WMI gefunden"
            }
        } catch {
            Write-Log "FEHLER beim Löschen von TS-Port $portName : $($_.Exception.Message)" "ERROR"
            Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
            $failedTSPorts++
        }
    }
}

Write-Host ""
Write-Host "=== LÖSCHE NB-PORTS ===" -ForegroundColor Cyan
Write-Host ""

$deletedNBPorts = 0
$failedNBPorts = 0

foreach ($port in $nbPorts) {
    $portName = $port.Name
    Write-Host "Verarbeite: $portName" -ForegroundColor Yellow
    
    try {
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "NB-Port gelöscht: $portName" "SUCCESS"
        Write-Host "  [OK] Port gelöscht" -ForegroundColor Green
        $deletedNBPorts++
    } catch {
        Write-Log "FEHLER beim Löschen von NB-Port $portName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        $failedNBPorts++
    }
}

Write-Host ""
Write-Host "=== LÖSCHE WH-PORTS ===" -ForegroundColor Cyan
Write-Host ""

$deletedWHPorts = 0
$failedWHPorts = 0

foreach ($port in $whPorts) {
    $portName = $port.Name
    Write-Host "Verarbeite: $portName" -ForegroundColor Yellow
    
    try {
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "WH-Port gelöscht: $portName" "SUCCESS"
        Write-Host "  [OK] Port gelöscht" -ForegroundColor Green
        $deletedWHPorts++
    } catch {
        Write-Log "FEHLER beim Löschen von WH-Port $portName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        $failedWHPorts++
    }
}

Write-Host ""
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host "Gelöschte umgeleitete Drucker: $deletedPrinters / $($redirectedPrinters.Count)" -ForegroundColor $(if ($deletedPrinters -eq $redirectedPrinters.Count) { "Green" } else { "Yellow" })
Write-Host "Fehlgeschlagene Drucker: $failedPrinters" -ForegroundColor $(if ($failedPrinters -eq 0) { "Green" } else { "Red" })
Write-Host "Gelöschte TS-Ports: $deletedTSPorts / $($tsPorts.Count)" -ForegroundColor $(if ($deletedTSPorts -eq $tsPorts.Count) { "Green" } else { "Yellow" })
Write-Host "Gelöschte NB-Ports: $deletedNBPorts / $($nbPorts.Count)" -ForegroundColor $(if ($deletedNBPorts -eq $nbPorts.Count) { "Green" } else { "Yellow" })
Write-Host "Gelöschte WH-Ports: $deletedWHPorts / $($whPorts.Count)" -ForegroundColor $(if ($deletedWHPorts -eq $whPorts.Count) { "Green" } else { "Yellow" })
Write-Host ""

$totalDeleted = $deletedPrinters + $deletedTSPorts + $deletedNBPorts + $deletedWHPorts
$totalFailed = $failedPrinters + $failedTSPorts + $failedNBPorts + $failedWHPorts

Write-Log "Zusammenfassung: $totalDeleted gelöscht, $totalFailed fehlgeschlagen" "INFO"
Write-Host "Log-Datei: $OutputLog" -ForegroundColor Gray
Write-Host ""

