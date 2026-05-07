# ==================================================================
# Phase 1: Bestandsaufnahme aller GPOs mit Drucker-Einstellungen
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\1.2-Bestandsaufnahme-GPOs_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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

# PrÃ¼fe ob GPMC verfÃ¼gbar ist
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Log "GroupPolicy-Modul geladen" "SUCCESS"
}
catch {
    Write-Log "FEHLER: GroupPolicy-Modul konnte nicht geladen werden. Bitte installieren Sie RSAT: Group Policy Management Tools" "ERROR"
    exit 1
}

Write-Log "=== Bestandsaufnahme GPOs gestartet ===" "INFO"

# Hole alle GPOs
$allGPOs = Get-GPO -All -ErrorAction Stop
$printerGPOs = @()

Write-Host "PrÃ¼fe $($allGPOs.Count) GPOs..." -ForegroundColor Cyan

foreach ($gpo in $allGPOs) {
    try {
        # PrÃ¼fe ob GPO-Namen "Drucker" oder "Printer" enthalten
        $containsPrinter = $gpo.DisplayName -like "*Drucker*" -or $gpo.DisplayName -like "*Printer*"
        
        # PrÃ¼fe ob GPO tatsÃ¤chlich Drucker-Einstellungen enthÃ¤lt
        $gpoReport = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction SilentlyContinue
        $hasPrinterSettings = $false
        
        if ($gpoReport) {
            $hasPrinterSettings = $gpoReport -match "Printer" -or $gpoReport -match "Print"
        }
        
        if ($containsPrinter -or $hasPrinterSettings) {
            Write-Log "Gefunden: $($gpo.DisplayName)" "INFO"
            
            # Hole VerknÃ¼pfungen
            $links = @()
            try {
                $domain = Get-ADDomain
                $allLinks = Get-GPInheritance -Target $domain.DistinguishedName -ErrorAction SilentlyContinue
                $gpoLinks = $allLinks | Where-Object { $_.GpoId -eq $gpo.Id }
                
                foreach ($link in $gpoLinks) {
                    $links += $link.Target
                }
            }
            catch {
                # Ignoriere Fehler
            }
            
            $gpoInfo = [PSCustomObject]@{
                GPOName = $gpo.DisplayName
                GPOId = $gpo.Id
                GPOStatus = $gpo.GpoStatus
                Created = $gpo.CreationTime
                Modified = $gpo.ModificationTime
                Description = $gpo.Description
                Links = $links -join "; "
                ContainsPrinterInName = $containsPrinter
                HasPrinterSettings = $hasPrinterSettings
            }
            
            $printerGPOs += $gpoInfo
        }
    }
    catch {
        Write-Log "Fehler beim PrÃ¼fen von $($gpo.DisplayName): $($_.Exception.Message)" "WARNING"
    }
}

# Exportiere Ergebnisse
if ($printerGPOs.Count -gt 0) {
    $csvFile = Join-Path $OutputDir "1.2-GPOs-Bestandsaufnahme.csv"
    $printerGPOs | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "GPO-Export erstellt: $csvFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Gefundene GPOs ===" -ForegroundColor Green
    Write-Host "Anzahl: $($printerGPOs.Count)" -ForegroundColor Green
    Write-Host ""
    
    foreach ($gpo in $printerGPOs) {
        Write-Host "  - $($gpo.GPOName)" -ForegroundColor Yellow
        Write-Host "    ID: $($gpo.GPOId)" -ForegroundColor Gray
    }
}
else {
    Write-Host "KEINE GPOs mit Drucker-Einstellungen gefunden!" -ForegroundColor Yellow
    Write-Log "KEINE GPOs mit Drucker-Einstellungen gefunden" "INFO"
}

Write-Host ""
Write-Host "Export-Datei: $(Join-Path $OutputDir '1.2-GPOs-Bestandsaufnahme.csv')" -ForegroundColor Cyan

Write-Log "=== Bestandsaufnahme GPOs abgeschlossen ===" "INFO"

