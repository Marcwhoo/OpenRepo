# ==================================================================
# Test-Script: Prüft ob alle Druckertreiber für Import-Drucker installiert sind
# ==================================================================
# 
# Dieses Script liest die Import-XML-Dateien und prüft für jeden Drucker,
# ob der benötigte Treiber auf dem Server installiert ist.
#
# Es erstellt eine Übersicht:
# - Welche Treiber benötigt werden (aus den Import-XML-Dateien)
# - Welche Treiber bereits installiert sind
# - Welche Treiber fehlen (müssen vor dem Import installiert werden)
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

$OutputDir = Split-Path $ScriptDir -Parent
$LogDir = Join-Path $OutputDir "Logs"
$LogFile = Join-Path $LogDir "Test-Printer-Drivers-From-Import_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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
Write-Host "=== PRÜFUNG DER DRUCKERTREIBER FÜR IMPORT-DRUCKER ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

Write-Log "=== Prüfung der Druckertreiber für Import-Drucker gestartet ===" "INFO"
Write-Log "Zielserver: $ComputerName" "INFO"

# SCHRITT 1: Import-XML-Dateien finden
Write-Host "=== SCHRITT 1: Import-XML-Dateien suchen ===" -ForegroundColor Cyan
Write-Log "Suche Import-XML-Dateien..." "INFO"

$importFiles = Get-ChildItem -Path $OutputDir -Filter "4.1-Import-*-Printers.xml" | Sort-Object Name

if ($importFiles.Count -eq 0) {
    Write-Log "FEHLER: Keine Import-XML-Dateien gefunden!" "ERROR"
    Write-Host "  [FEHLER] Keine Import-XML-Dateien gefunden in: $OutputDir" -ForegroundColor Red
    Write-Host "  Erwartete Dateien: 4.1-Import-*-Printers.xml" -ForegroundColor Yellow
    exit 1
}

Write-Log "Gefunden: $($importFiles.Count) Import-XML-Dateien" "SUCCESS"
Write-Host "  [OK] Gefunden: $($importFiles.Count) Import-XML-Dateien" -ForegroundColor Green
foreach ($file in $importFiles) {
    Write-Host "    - $($file.Name)" -ForegroundColor Gray
}
Write-Host ""

# SCHRITT 2: Alle installierten Treiber abrufen
Write-Host "=== SCHRITT 2: Installierte Treiber abrufen ===" -ForegroundColor Cyan
Write-Log "Rufe alle installierten Treiber vom Server ab..." "INFO"

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

# SCHRITT 3: Drucker aus XML-Dateien extrahieren
Write-Host "=== SCHRITT 3: Drucker aus Import-XML-Dateien extrahieren ===" -ForegroundColor Cyan
Write-Host ""

$allPrinters = @()
$requiredDrivers = @{}
$missingDrivers = @{}

foreach ($file in $importFiles) {
    $fileName = $file.Name
    $filePath = $file.FullName
    
    Write-Host "Verarbeite: $fileName" -ForegroundColor Yellow
    Write-Log "Verarbeite Datei: $fileName" "INFO"
    
    try {
        # Lade XML
        [xml]$xml = Get-Content -Path $filePath -Encoding UTF8
        
        # Namespace-Manager für XPath
        $nsManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
        
        # Finde alle Drucker-Objekte
        $printerObjects = $xml.SelectNodes("//ps:Objs/ps:Obj", $nsManager)
        
        Write-Log "Gefunden: $($printerObjects.Count) Drucker-Objekte in $fileName" "INFO"
        Write-Host "  Gefunden: $($printerObjects.Count) Drucker" -ForegroundColor Gray
        
        foreach ($obj in $printerObjects) {
            # Extrahiere Drucker-Name
            $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
            if (-not $nameProp) {
                continue
            }
            $printerName = $nameProp.InnerText
            
            # Extrahiere DriverName
            $driverProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='DriverName']", $nsManager)
            $driverName = if ($driverProp) { $driverProp.InnerText } else { "" }
            
            # Extrahiere PortName
            $portProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PortName']", $nsManager)
            $portName = if ($portProp) { $portProp.InnerText } else { "" }
            
            if ([string]::IsNullOrWhiteSpace($driverName)) {
                Write-Log "  WARNUNG: Drucker '$printerName' hat keinen Treiber in XML!" "WARNING"
                Write-Host "    [WARNUNG] $printerName - Kein Treiber in XML" -ForegroundColor Yellow
                
                $allPrinters += [PSCustomObject]@{
                    SourceFile = $fileName
                    PrinterName = $printerName
                    DriverName = "(kein Treiber)"
                    DriverInstalled = $false
                    Status = "KEIN_TREIBER"
                    PortName = $portName
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
                    SourceFiles = @()
                }
            }
            
            $requiredDrivers[$driverName].PrinterCount++
            $requiredDrivers[$driverName].Printers += $printerName
            if ($fileName -notin $requiredDrivers[$driverName].SourceFiles) {
                $requiredDrivers[$driverName].SourceFiles += $fileName
            }
            
            if (-not $isInstalled) {
                if (-not $missingDrivers.ContainsKey($driverName)) {
                    $missingDrivers[$driverName] = @{
                        DriverName = $driverName
                        PrinterCount = 0
                        Printers = @()
                        SourceFiles = @()
                    }
                }
                $missingDrivers[$driverName].PrinterCount++
                $missingDrivers[$driverName].Printers += $printerName
                if ($fileName -notin $missingDrivers[$driverName].SourceFiles) {
                    $missingDrivers[$driverName].SourceFiles += $fileName
                }
            }
            
            $status = if ($isInstalled) { "OK" } else { "FEHLT" }
            $statusColor = if ($isInstalled) { "Green" } else { "Red" }
            
            Write-Host "    [$status] $printerName" -ForegroundColor $statusColor
            Write-Host "             Treiber: $driverName" -ForegroundColor Gray
            
            if (-not $isInstalled) {
                Write-Log "  FEHLT: Drucker '$printerName' benötigt Treiber '$driverName' (nicht installiert)" "ERROR"
            } else {
                Write-Log "  OK: Drucker '$printerName' - Treiber '$driverName' ist installiert" "INFO"
            }
            
            $allPrinters += [PSCustomObject]@{
                SourceFile = $fileName
                PrinterName = $printerName
                DriverName = $driverName
                DriverInstalled = $isInstalled
                Status = $status
                PortName = $portName
            }
        }
        
        Write-Host ""
        
    } catch {
        Write-Log "FEHLER beim Verarbeiten von $fileName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
    }
}

Write-Host ""

# SCHRITT 4: Zusammenfassung
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

$totalPrinters = $allPrinters.Count
$printersWithDriver = ($allPrinters | Where-Object { $_.DriverInstalled -eq $true }).Count
$printersWithoutDriver = ($allPrinters | Where-Object { $_.DriverInstalled -eq $false -and $_.Status -ne "KEIN_TREIBER" }).Count
$printersNoDriver = ($allPrinters | Where-Object { $_.Status -eq "KEIN_TREIBER" }).Count

Write-Host "Drucker-Statistik (aus Import-XML-Dateien):" -ForegroundColor Yellow
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
    Write-Host "=== FEHLENDE TREIBER (MÜSSEN INSTALLIERT WERDEN) ===" -ForegroundColor Red
    Write-Host ""
    
    foreach ($driverName in ($missingDrivers.Keys | Sort-Object)) {
        $driverInfo = $missingDrivers[$driverName]
        Write-Host "  Treiber: $driverName" -ForegroundColor Red
        Write-Host "    Wird benötigt von $($driverInfo.PrinterCount) Drucker(n) in:" -ForegroundColor Yellow
        
        foreach ($sourceFile in $driverInfo.SourceFiles) {
            Write-Host "      - $sourceFile" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "    Betroffene Drucker:" -ForegroundColor Yellow
        foreach ($printerName in $driverInfo.Printers) {
            Write-Host "      - $printerName" -ForegroundColor Gray
        }
        Write-Host ""
        
        Write-Log "FEHLENDER TREIBER: $driverName (benötigt von $($driverInfo.PrinterCount) Druckern)" "ERROR"
    }
    
    Write-Host "  [WARNUNG] Bitte installieren Sie die fehlenden Treiber vor dem Import!" -ForegroundColor Red
    Write-Host ""
} else {
    Write-Host "=== ALLE TREIBER INSTALLIERT ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "  [OK] Alle benötigten Treiber sind installiert!" -ForegroundColor Green
    Write-Host "  [OK] Der Import kann durchgeführt werden!" -ForegroundColor Green
    Write-Log "Alle benötigten Treiber sind installiert - Import kann durchgeführt werden" "SUCCESS"
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
    Write-Host "      In Datei(en): $($driverInfo.SourceFiles -join ', ')" -ForegroundColor Gray
    Write-Host ""
}

# Export zu CSV (optional)
if ($ExportCSV) {
    $csvFile = Join-Path $LogDir "Test-Printer-Drivers-From-Import_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    try {
        $allPrinters | Export-Csv -Path $csvFile -Encoding UTF8 -NoTypeInformation -Delimiter ";"
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

# Exit-Code basierend auf fehlenden Treibern
if ($missingDrivers.Count -gt 0) {
    Write-Host "  [INFO] Exit-Code: 1 (fehlende Treiber gefunden)" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "  [INFO] Exit-Code: 0 (alle Treiber installiert)" -ForegroundColor Green
    exit 0
}


