# ==================================================================
# Setzt alle Druckertreiber auf Universal Print Class Driver
# ==================================================================
# 
# Dieses Script ändert alle DriverName in den Import-XML-Dateien
# auf "Universal Print Class Driver" um.
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$UniversalDriverName = "Universal Print Class Driver"
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
$LogFile = Join-Path $LogDir "4.4-Setze-Universal-Druckertreiber_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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
Write-Host "=== SETZE UNIVERSAL PRINT DRIVER ===" -ForegroundColor Cyan
Write-Host "Treiber: $UniversalDriverName" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

# Prüfe ob Treiber auf Zielserver vorhanden ist
Write-Host "Prüfe Treiber auf <PRINT-SERVER-1>-01..." -ForegroundColor Cyan
try {
    $treiber = Get-PrinterDriver -ComputerName "<PRINT-SERVER-1>-01" -Name $UniversalDriverName -ErrorAction Stop
    Write-Log "Treiber '$UniversalDriverName' ist auf <PRINT-SERVER-1>-01 installiert" "SUCCESS"
    Write-Host "  [OK] Treiber ist installiert" -ForegroundColor Green
} catch {
    Write-Log "FEHLER: Treiber '$UniversalDriverName' ist NICHT auf <PRINT-SERVER-1>-01 installiert!" "ERROR"
    Write-Host "  [FEHLER] Treiber ist nicht installiert!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Bitte installieren Sie den Treiber zuerst:" -ForegroundColor Yellow
    Write-Host "  Add-PrinterDriver -Name '$UniversalDriverName' -ComputerName <PRINT-SERVER-1>-01" -ForegroundColor Gray
    exit 1
}

Write-Host ""

# Finde alle Import-XML-Dateien (nur Printers, nicht Ports)
$printersFiles = Get-ChildItem -Path $OutputDir -Filter "4.1-Import-*-Printers.xml" | Sort-Object Name

if ($printersFiles.Count -eq 0) {
    Write-Log "FEHLER: Keine Import-XML-Dateien gefunden!" "ERROR"
    Write-Host "  [FEHLER] Keine Import-XML-Dateien gefunden!" -ForegroundColor Red
    exit 1
}

Write-Log "Gefunden: $($printersFiles.Count) Drucker-XML-Dateien" "INFO"
Write-Host "Gefundene Dateien: $($printersFiles.Count)" -ForegroundColor Cyan
Write-Host ""

$totalChanged = 0

foreach ($file in $printersFiles) {
    $filePath = $file.FullName
    $fileName = $file.Name
    
    Write-Host "Verarbeite: $fileName" -ForegroundColor Yellow
    Write-Log "Verarbeite: $fileName" "INFO"
    
    try {
        # Lade XML
        [xml]$xml = Get-Content -Path $filePath -Encoding UTF8
        
        # Namespace-Manager für XPath
        $nsManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
        
        $changed = 0
        
        # Finde alle Drucker-Objekte
        foreach ($obj in $xml.SelectNodes("//ps:Objs/ps:Obj", $nsManager)) {
            # Finde DriverName-Property
            $driverProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='DriverName']", $nsManager)
            
            if ($driverProp) {
                $oldDriver = $driverProp.InnerText
                if ($oldDriver -ne $UniversalDriverName) {
                    $driverProp.InnerText = $UniversalDriverName
                    $changed++
                    Write-Log "  Treiber geändert: '$oldDriver' -> '$UniversalDriverName'" "INFO"
                }
            }
        }
        
        # Speichere XML
        $xml.Save($filePath)
        
        Write-Log "Datei aktualisiert: $fileName ($changed Treiber geändert)" "SUCCESS"
        Write-Host "  [OK] $changed Treiber geändert" -ForegroundColor Green
        
        $totalChanged += $changed
        
    } catch {
        Write-Log "FEHLER beim Verarbeiten von $fileName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host "Gesamt geänderte Treiber: $totalChanged" -ForegroundColor Green
Write-Log "Zusammenfassung: $totalChanged Treiber geändert" "INFO"
Write-Host ""
Write-Host "Die XML-Dateien wurden aktualisiert." -ForegroundColor Green
Write-Host "Sie können jetzt den Import starten." -ForegroundColor Yellow
Write-Host ""

