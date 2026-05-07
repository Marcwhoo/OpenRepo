# ==================================================================
# Phase 2.5: Filtert Printbrm-Export-Dateien - entfernt Drucker und Ports
# Behält nur die Treiber in den Export-Dateien
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$ExportDir = Join-Path $ScriptDir "Export"
$LogDir = Join-Path $ScriptDir "Logs"
$LogFile = Join-Path $LogDir "2.5-Filtere-Driver-Export_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Log-Verzeichnis
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Logging-Funktion
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

Write-Host ""
Write-Host "=== FILTERE DRIVER-EXPORT-DATEIEN ===" -ForegroundColor Cyan
Write-Host "Export-Ordner: $ExportDir" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

# Prüfe ob Export-Ordner existiert
if (-not (Test-Path $ExportDir)) {
    Write-Log "FEHLER: Export-Ordner nicht gefunden: $ExportDir" "ERROR"
    Write-Host "  [FEHLER] Export-Ordner nicht gefunden!" -ForegroundColor Red
    exit 1
}

# Finde alle .printerexport Dateien
$exportFiles = Get-ChildItem -Path $ExportDir -Filter "*.printerexport"

if ($exportFiles.Count -eq 0) {
    Write-Log "FEHLER: Keine .printerexport Dateien gefunden!" "ERROR"
    Write-Host "  [FEHLER] Keine .printerexport Dateien gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "Gefundene Export-Dateien: $($exportFiles.Count)" -ForegroundColor Green
foreach ($file in $exportFiles) {
    Write-Host "  - $($file.Name)" -ForegroundColor Gray
}
Write-Host ""

# Funktion zum Entpacken von CAB
function Expand-CabFile {
    param(
        [string]$CabPath,
        [string]$DestPath
    )
    
    try {
        # Verwende Shell.Application COM-Objekt zum Entpacken
        $shell = New-Object -ComObject Shell.Application
        $cabFolder = $shell.NameSpace($CabPath)
        
        if ($null -eq $cabFolder) {
            throw "CAB-Datei konnte nicht geöffnet werden"
        }
        
        $destFolder = $shell.NameSpace($DestPath)
        if ($null -eq $destFolder) {
            New-Item -Path $DestPath -ItemType Directory -Force | Out-Null
            $destFolder = $shell.NameSpace($DestPath)
        }
        
        # Kopiere alle Dateien aus der CAB
        $cabFolder.Items() | ForEach-Object {
            $destFolder.CopyHere($_, 0x14) # 0x14 = keine Dialoge, überschreibe wenn nötig
        }
        
        # Warte kurz, damit der Kopiervorgang abgeschlossen wird
        Start-Sleep -Seconds 2
        
        return $true
    } catch {
        Write-Log "FEHLER beim Entpacken: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Funktion zum Erstellen von CAB
function New-CabFile {
    param(
        [string]$SourcePath,
        [string]$CabPath
    )
    
    try {
        # Erstelle DDF-Datei für makecab
        $ddfPath = Join-Path (Split-Path $CabPath) "temp.ddf"
        $cabName = Split-Path $CabPath -Leaf
        
        $ddfContent = @"
.OPTION EXPLICIT
.Set CabinetNameTemplate=$cabName
.Set DiskDirectoryTemplate=.
.Set CompressionType=MSZIP
.Set UniqueFiles="OFF"
.Set Cabinet=ON
.Set Compress=ON
"@
        
        # Füge alle Dateien hinzu
        Get-ChildItem -Path $SourcePath -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Replace($SourcePath, "").TrimStart('\').Replace('\', '/')
            $ddfContent += "`n`"$($_.FullName)`" `"$relativePath`""
        }
        
        $ddfContent | Out-File -FilePath $ddfPath -Encoding ASCII -Force
        
        # Erstelle CAB mit makecab
        Push-Location (Split-Path $CabPath)
        $makecabResult = & makecab.exe /F $ddfPath 2>&1
        Pop-Location
        
        if ($LASTEXITCODE -ne 0) {
            throw "Makecab fehlgeschlagen: $makecabResult"
        }
        
        # Verschiebe erstellte CAB-Datei
        $createdCab = Join-Path (Split-Path $CabPath) $cabName
        if (Test-Path $createdCab) {
            if (Test-Path $CabPath) {
                Remove-Item -Path $CabPath -Force
            }
            Move-Item -Path $createdCab -Destination $CabPath -Force
        }
        
        # Lösche DDF-Datei und Setup-Dateien
        Remove-Item -Path $ddfPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path (Split-Path $CabPath) "setup.inf") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path (Split-Path $CabPath) "setup.rpt") -Force -ErrorAction SilentlyContinue
        
        return $true
    } catch {
        Write-Log "FEHLER beim Erstellen von CAB: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Verarbeite jede Export-Datei
foreach ($exportFile in $exportFiles) {
    $fileName = $exportFile.BaseName
    $filePath = $exportFile.FullName
    
    Write-Host "=== Verarbeite: $($exportFile.Name) ===" -ForegroundColor Yellow
    Write-Log "Verarbeite: $($exportFile.Name)" "INFO"
    
    # Erstelle temporären Ordner
    $tempDir = Join-Path $ExportDir "temp-$fileName"
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
    try {
        # Schritt 1: Benenne .printerexport zu .cab um (kopiere statt umbenennen)
        $cabPath = Join-Path $ExportDir "$fileName.cab"
        Copy-Item -Path $filePath -Destination $cabPath -Force
        Write-Log "Datei kopiert als CAB: $cabPath" "INFO"
        
        # Schritt 2: Entpacke CAB
        Write-Host "  Entpacke CAB..." -ForegroundColor Cyan
        if (-not (Expand-CabFile -CabPath $cabPath -DestPath $tempDir)) {
            throw "Entpacken fehlgeschlagen"
        }
        Write-Log "CAB entpackt nach: $tempDir" "SUCCESS"
        
        # Schritt 3: Finde und bearbeite manifest.xml
        # Suche nach manifest.xml (kann im Root oder in Unterordnern sein)
        $foundManifest = Get-ChildItem -Path $tempDir -Filter "manifest.xml" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $foundManifest) {
            # Liste alle Dateien für Debugging
            Write-Log "Verfügbare Dateien im temp-Ordner:" "INFO"
            Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
                Write-Log "  - $($_.FullName)" "INFO"
            }
            throw "manifest.xml nicht gefunden"
        }
        
        $manifestPath = $foundManifest.FullName
        
        Write-Host "  Bearbeite manifest.xml..." -ForegroundColor Cyan
        Write-Log "Bearbeite manifest.xml: $manifestPath" "INFO"
        
        # Lade XML
        [xml]$xml = Get-Content -Path $manifestPath -Encoding UTF8
        
        # Zähle vorher
        $printQueuesBefore = $xml.SelectNodes("//PrintQueue").Count
        $portsBefore = $xml.SelectNodes("//Port").Count
        $driversBefore = $xml.SelectNodes("//Driver").Count
        
        Write-Host "    Vorher: $printQueuesBefore Drucker, $portsBefore Ports, $driversBefore Treiber" -ForegroundColor Gray
        
        # Entferne alle PrintQueue-Knoten
        $removedQueues = 0
        $xml.SelectNodes("//PrintQueue") | ForEach-Object {
            $_.ParentNode.RemoveChild($_) | Out-Null
            $removedQueues++
        }
        
        # Entferne alle Port-Knoten
        $removedPorts = 0
        $xml.SelectNodes("//Port") | ForEach-Object {
            $_.ParentNode.RemoveChild($_) | Out-Null
            $removedPorts++
        }
        
        # Zähle nachher
        $driversAfter = $xml.SelectNodes("//Driver").Count
        
        Write-Host "    Nachher: 0 Drucker, 0 Ports, $driversAfter Treiber" -ForegroundColor Green
        Write-Log "Entfernt: $removedQueues Drucker, $removedPorts Ports. Behalten: $driversAfter Treiber" "INFO"
        
        # Speichere bearbeitete XML
        $xml.Save($manifestPath)
        Write-Log "manifest.xml gespeichert" "SUCCESS"
        
        # Schritt 4: Erstelle neue CAB
        Write-Host "  Erstelle neue CAB..." -ForegroundColor Cyan
        $newCabPath = Join-Path $ExportDir "$fileName-drivers-only.cab"
        
        if (-not (New-CabFile -SourcePath $tempDir -CabPath $newCabPath)) {
            throw "CAB-Erstellung fehlgeschlagen"
        }
        
        # Schritt 5: Benenne zurück zu .printerexport
        $newExportPath = Join-Path $ExportDir "$fileName-drivers-only.printerexport"
        if (Test-Path $newExportPath) {
            Remove-Item -Path $newExportPath -Force
        }
        Move-Item -Path $newCabPath -Destination $newExportPath -Force
        Write-Log "Neue Export-Datei erstellt: $newExportPath" "SUCCESS"
        
        # Schritt 6: Aufräumen
        Remove-Item -Path $cabPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "  [OK] Fertig: $newExportPath" -ForegroundColor Green
        Write-Host ""
        
    } catch {
        Write-Log "FEHLER beim Verarbeiten von $($exportFile.Name): $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        
        # Aufräumen bei Fehler
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "=== FILTERUNG ABGESCHLOSSEN ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Die gefilterten Dateien haben den Suffix '-drivers-only'" -ForegroundColor Yellow
Write-Host "Diese können jetzt importiert werden (nur Treiber, keine Drucker/Ports)" -ForegroundColor Green
Write-Host ""
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""
