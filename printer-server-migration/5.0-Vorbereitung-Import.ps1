# ==================================================================
# Vorbereitung für Phase 5: Import
# ==================================================================
# 
# Dieses Script führt die Vorbereitungsschritte für den Import durch:
# - Prüft PrintManagement Module
# - Prüft Verbindung zum Zielserver
# - Erstellt Backup des aktuellen Printserver-Zustands
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = $null
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
$BackupDir = Join-Path $OutputDir "Backups"
$VorbereitungLogFile = Join-Path $LogDir "5.0-Vorbereitung-Import_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Verzeichnisse falls nicht vorhanden
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
}

# Logging-Funktion
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $VorbereitungLogFile -Value $logMessage -Encoding UTF8
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Host ""
Write-Host "=== VORBEREITUNG FÜR PHASE 5: IMPORT ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host "Log-Datei: $VorbereitungLogFile" -ForegroundColor Gray
Write-Host ""

$fehler = 0

# ==================================================================
# SCHRITT 1: PrintManagement Module prüfen
# ==================================================================
Write-Host "=== SCHRITT 1: PrintManagement Module ===" -ForegroundColor Cyan
Write-Host ""

Write-Log "Prüfe PrintManagement Module..." "INFO"
if (-not (Get-Module -ListAvailable -Name PrintManagement)) {
    Write-Log "PrintManagement Module nicht gefunden. Versuche Installation..." "WARNING"
    Write-Host "PrintManagement Module wird installiert..." -ForegroundColor Yellow
    
    try {
        Install-Module -Name PrintManagement -Scope CurrentUser -Force -ErrorAction Stop
        Write-Log "PrintManagement Module erfolgreich installiert" "SUCCESS"
        Write-Host "  [OK] PrintManagement Module installiert" -ForegroundColor Green
    } catch {
        Write-Log "FEHLER: PrintManagement Module konnte nicht installiert werden: $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] Installation fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Bitte installieren Sie das Modul manuell mit: Install-Module -Name PrintManagement" -ForegroundColor Yellow
        $fehler++
    }
} else {
    Write-Log "PrintManagement Module gefunden" "SUCCESS"
    Write-Host "  [OK] PrintManagement Module ist verfügbar" -ForegroundColor Green
}

# Lade PrintManagement Module
if ($fehler -eq 0) {
    try {
        Import-Module PrintManagement -ErrorAction Stop
        Write-Log "PrintManagement Module geladen" "SUCCESS"
        Write-Host "  [OK] PrintManagement Module geladen" -ForegroundColor Green
    } catch {
        Write-Log "FEHLER: PrintManagement Module konnte nicht geladen werden: $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] Modul konnte nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
        $fehler++
    }
}

Write-Host ""

# ==================================================================
# SCHRITT 2: Verbindung zum Zielserver prüfen
# ==================================================================
Write-Host "=== SCHRITT 2: Verbindung zum Zielserver ===" -ForegroundColor Cyan
Write-Host ""

Write-Log "Prüfe Verbindung zu $ComputerName..." "INFO"
try {
    $connection = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
    if (-not $connection) {
        Write-Log "FEHLER: Keine Verbindung zu $ComputerName möglich" "ERROR"
        Write-Host "  [FEHLER] Keine Verbindung zu $ComputerName möglich" -ForegroundColor Red
        $fehler++
    } else {
        Write-Log "Verbindung zu $ComputerName erfolgreich" "SUCCESS"
        Write-Host "  [OK] Verbindung zu $ComputerName erfolgreich" -ForegroundColor Green
        
        # Prüfe ob Print-Services verfügbar sind
        try {
            $printers = Get-Printer -ComputerName $ComputerName -ErrorAction SilentlyContinue
            Write-Log "Print-Services sind verfügbar. Aktuell $($printers.Count) Drucker auf dem Server" "INFO"
            Write-Host "  [OK] Print-Services verfügbar ($($printers.Count) Drucker gefunden)" -ForegroundColor Green
        } catch {
            Write-Log "WARNUNG: Konnte Druckerliste nicht abrufen: $($_.Exception.Message)" "WARNING"
            Write-Host "  [WARNUNG] Konnte Druckerliste nicht abrufen (möglicherweise Berechtigungsproblem)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Log "FEHLER: Verbindung fehlgeschlagen: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] Verbindung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    $fehler++
}

Write-Host ""

# ==================================================================
# SCHRITT 3: Backup des aktuellen Printserver-Zustands
# ==================================================================
Write-Host "=== SCHRITT 3: Backup des Printserver-Zustands ===" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $BackupPath = Join-Path $BackupDir "Backup-$ComputerName-$timestamp.xml"
}

Write-Log "Erstelle Backup des Printserver-Zustands..." "INFO"
Write-Log "Backup-Pfad: $BackupPath" "INFO"

try {
    # Exportiere aktuelle Drucker-Konfiguration
    $printers = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
    $ports = Get-PrinterPort -ComputerName $ComputerName -ErrorAction Stop
    
    if ($printers.Count -gt 0 -or $ports.Count -gt 0) {
        # Erstelle Backup-Objekt
        $backupData = @{
            ComputerName = $ComputerName
            BackupDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Printers = $printers
            Ports = $ports
        }
        
        # Exportiere als XML
        $backupData | Export-Clixml -Path $BackupPath -Depth 10 -ErrorAction Stop
        
        Write-Log "Backup erfolgreich erstellt: $BackupPath" "SUCCESS"
        Write-Log "  - Drucker: $($printers.Count)" "INFO"
        Write-Log "  - Ports: $($ports.Count)" "INFO"
        Write-Host "  [OK] Backup erstellt: $BackupPath" -ForegroundColor Green
        Write-Host "    - Drucker: $($printers.Count)" -ForegroundColor Gray
        Write-Host "    - Ports: $($ports.Count)" -ForegroundColor Gray
    } else {
        Write-Log "WARNUNG: Keine Drucker oder Ports gefunden auf $ComputerName" "WARNING"
        Write-Host "  [INFO] Keine Drucker oder Ports gefunden (Server ist leer)" -ForegroundColor Gray
    }
} catch {
    Write-Log "FEHLER: Backup konnte nicht erstellt werden: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] Backup fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  WARNUNG: Es wird empfohlen, vor dem Import ein manuelles Backup zu erstellen!" -ForegroundColor Yellow
    $fehler++
}

Write-Host ""

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

if ($fehler -eq 0) {
    Write-Host "[OK] ALLE VORBEREITUNGSSCHRITTE ERFOLGREICH!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Nächste Schritte:" -ForegroundColor Yellow
    Write-Host "  1. Führen Sie das Import-Script aus:" -ForegroundColor Gray
    Write-Host "     .\5.1-Importiere-Druckkonfiguration.ps1 -ComputerName $ComputerName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Bei Bedarf können Sie den Import rückgängig machen:" -ForegroundColor Gray
    Write-Host "     .\5.2-Fallback-Loesche-Importierte-Drucker.ps1 -ComputerName $ComputerName" -ForegroundColor Gray
} else {
    Write-Host "[FEHLER] EINIGE VORBEREITUNGSSCHRITTE SIND FEHLGESCHLAGEN!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Bitte beheben Sie die Fehler vor dem Import!" -ForegroundColor Red
    Write-Host "Anzahl Fehler: $fehler" -ForegroundColor Red
}

Write-Host ""
Write-Log "Vorbereitung abgeschlossen" "INFO"
Write-Log "Log-Datei: $VorbereitungLogFile" "INFO"
if (-not [string]::IsNullOrWhiteSpace($BackupPath) -and (Test-Path $BackupPath)) {
    Write-Log "Backup-Datei: $BackupPath" "INFO"
}

Write-Host ""

