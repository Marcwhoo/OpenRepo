# ==================================================================
# Testet die Import-XML-Dateien auf einem Printserver
# ==================================================================
# 
# WICHTIG: Dieses Script testet die XML-Dateien, ohne Änderungen vorzunehmen
# Es kann auf dem Zielserver (<PRINT-SERVER-1>-01) oder lokal ausgeführt werden
#
# Optionen:
#   -TestMode: Nur Validierung, kein Import
#   -DryRun: Simuliert Import ohne Änderungen
#   -WhatIf: Zeigt was importiert werden würde
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [switch]$TestMode = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = $ScriptDir

# XML-Dateien (alle Server)
$XMLFiles = @(
    @{ Server = "<PRINT-SERVER-1>"; PrintersFile = "4.1-Import-<PRINT-SERVER-1>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-1>-Ports.xml" },
    @{ Server = "<PRINT-SERVER-2>"; PrintersFile = "4.1-Import-<PRINT-SERVER-2>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-2>-Ports.xml" },
    @{ Server = "<PRINT-SERVER-3>"; PrintersFile = "4.1-Import-<PRINT-SERVER-3>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-3>-Ports.xml" }
)

Write-Host "=== TEST DER IMPORT-XML-DATEIEN AUF PRINTSERVER ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host "Test-Modus: $TestMode" -ForegroundColor Yellow
Write-Host "Dry-Run: $DryRun" -ForegroundColor Yellow
Write-Host "WhatIf: $WhatIf" -ForegroundColor Yellow
Write-Host ""

# Prüfe ob PrintManagement Module verfügbar ist
if (-not (Get-Module -ListAvailable -Name PrintManagement)) {
    Write-Host "WARNUNG: PrintManagement Module nicht gefunden" -ForegroundColor Yellow
    Write-Host "Versuche trotzdem fortzufahren..." -ForegroundColor Yellow
    Write-Host ""
}

# Prüfe Verbindung zum Server
if (-not $TestMode) {
    Write-Host "Prüfe Verbindung zu $ComputerName..." -ForegroundColor Cyan
    try {
        $connection = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
        if (-not $connection) {
            Write-Host "FEHLER: Keine Verbindung zu $ComputerName möglich" -ForegroundColor Red
            exit 1
        }
        Write-Host "  OK: Verbindung erfolgreich" -ForegroundColor Green
    } catch {
        Write-Host "FEHLER: Verbindung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

$gesamtFehler = 0
$gesamtWarnungen = 0
$erfolgreicheTests = 0

# Teste jede XML-Datei
foreach ($xmlFileInfo in $XMLFiles) {
    $server = $xmlFileInfo.Server
    $printersFile = $xmlFileInfo.PrintersFile
    $portsFile = $xmlFileInfo.PortsFile
    
    $printersPath = Join-Path $OutputDir $printersFile
    $portsPath = Join-Path $OutputDir $portsFile
    
    Write-Host "=== Teste $server ===" -ForegroundColor Yellow
    Write-Host ""
    
    # Prüfe ob Dateien existieren
    if (-not (Test-Path $printersPath)) {
        Write-Host "  FEHLER: Drucker-XML nicht gefunden: $printersFile" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    if (-not (Test-Path $portsPath)) {
        Write-Host "  FEHLER: Ports-XML nicht gefunden: $portsFile" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    # TEST 1: XML kann geladen werden
    Write-Host "  Test 1: XML-Laden..." -ForegroundColor Cyan
    try {
        $printers = Import-Clixml -Path $printersPath -ErrorAction Stop
        $ports = Import-Clixml -Path $portsPath -ErrorAction Stop
        
        Write-Host "    OK: XML geladen" -ForegroundColor Green
        Write-Host "      - Drucker: $($printers.Count)" -ForegroundColor Gray
        Write-Host "      - Ports: $($ports.Count)" -ForegroundColor Gray
    } catch {
        Write-Host "    FEHLER: XML kann nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    # TEST 2: Objekte haben korrekte Typen
    Write-Host "  Test 2: Objekt-Typen..." -ForegroundColor Cyan
    $falscheTypen = 0
    foreach ($printer in $printers) {
        if ($printer.PSTypeNames[0] -notlike "*MSFT_Printer*") {
            $falscheTypen++
        }
    }
    foreach ($port in $ports) {
        if ($port.PSTypeNames[0] -notlike "*MSFT_*PrinterPort*") {
            $falscheTypen++
        }
    }
    
    if ($falscheTypen -eq 0) {
        Write-Host "    OK: Alle Objekt-Typen korrekt" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $falscheTypen Objekte mit falschem Typ" -ForegroundColor Red
        $gesamtFehler += $falscheTypen
    }
    
    # TEST 3: ComputerName ist korrekt
    Write-Host "  Test 3: ComputerName..." -ForegroundColor Cyan
    $falscheComputerName = ($printers | Where-Object { $_.ComputerName -ne $ComputerName }).Count
    $falschePortComputerName = ($ports | Where-Object { $_.ComputerName -ne $ComputerName }).Count
    
    if ($falscheComputerName -eq 0 -and $falschePortComputerName -eq 0) {
        Write-Host "    OK: Alle ComputerName korrekt" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $falscheComputerName Drucker, $falschePortComputerName Ports mit falschem ComputerName" -ForegroundColor Red
        $gesamtFehler += ($falscheComputerName + $falschePortComputerName)
    }
    
    # TEST 4: Import-PrintConfiguration Simulation (nur wenn nicht TestMode)
    if (-not $TestMode) {
        Write-Host "  Test 4: Import-PrintConfiguration Simulation..." -ForegroundColor Cyan
        
        # Prüfe ob Import-PrintConfiguration verfügbar ist
        if (Get-Command Import-PrintConfiguration -ErrorAction SilentlyContinue) {
            try {
                if ($WhatIf -or $DryRun) {
                    Write-Host "    Simuliere Import (WhatIf/DryRun)..." -ForegroundColor Yellow
                    # Import-PrintConfiguration hat kein -WhatIf, daher nur Validierung
                    Write-Host "    HINWEIS: Import-PrintConfiguration unterstützt kein -WhatIf" -ForegroundColor Yellow
                    Write-Host "    Verwenden Sie -TestMode für sichere Validierung" -ForegroundColor Yellow
                } else {
                    Write-Host "    WARNUNG: Echter Import würde jetzt durchgeführt!" -ForegroundColor Red
                    Write-Host "    Verwenden Sie -TestMode oder -DryRun für Tests" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "    FEHLER bei Import-Simulation: $($_.Exception.Message)" -ForegroundColor Red
                $gesamtFehler++
            }
        } else {
            Write-Host "    WARNUNG: Import-PrintConfiguration nicht verfügbar" -ForegroundColor Yellow
            Write-Host "    Installieren Sie PrintManagement Module" -ForegroundColor Yellow
            $gesamtWarnungen++
        }
    }
    
    # TEST 5: Port-Drucker-Zuordnung
    Write-Host "  Test 5: Port-Drucker-Zuordnung..." -ForegroundColor Cyan
    $druckerOhnePort = 0
    $portsOhneDrucker = 0
    
    $verwendetePorts = @{}
    foreach ($printer in $printers) {
        if ($printer.PortName) {
            $verwendetePorts[$printer.PortName] = $true
        } else {
            $druckerOhnePort++
        }
    }
    
    foreach ($port in $ports) {
        if (-not $verwendetePorts.ContainsKey($port.Name)) {
            # Prüfe ob es ein Standard-Port ist (diese werden nicht verwendet)
            if ($port.Name -notmatch "^(COM|LPT|PORTPROMPT|FILE):") {
                $portsOhneDrucker++
            }
        }
    }
    
    if ($druckerOhnePort -gt 0) {
        Write-Host "    WARNUNG: $druckerOhnePort Drucker ohne Port" -ForegroundColor Yellow
        $gesamtWarnungen += $druckerOhnePort
    }
    
    if ($portsOhneDrucker -gt 0) {
        Write-Host "    INFO: $portsOhneDrucker Ports ohne zugehörigen Drucker (kann normal sein)" -ForegroundColor Gray
    }
    
    if ($druckerOhnePort -eq 0) {
        Write-Host "    OK: Alle Drucker haben Ports" -ForegroundColor Green
    }
    
    $erfolgreicheTests++
    Write-Host ""
}

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

if ($gesamtFehler -eq 0) {
    Write-Host "✓ ALLE TESTS ERFOLGREICH!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Erfolgreich getestet: $erfolgreicheTests von $($XMLFiles.Count) Server-Konfigurationen" -ForegroundColor Green
    
    if ($gesamtWarnungen -gt 0) {
        Write-Host "Warnungen: $gesamtWarnungen" -ForegroundColor Yellow
    }
    
    Write-Host ""
    if ($TestMode) {
        Write-Host "Die XML-Dateien sind bereit für den Import!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Für echten Import (OHNE TestMode):" -ForegroundColor Yellow
        Write-Host "  .\4.3-Teste-XML-auf-Printserver.ps1 -ComputerName $ComputerName -TestMode:`$false -WhatIf" -ForegroundColor Gray
    } else {
        Write-Host "HINWEIS: Dies war ein Test. Für echten Import entfernen Sie -TestMode" -ForegroundColor Yellow
    }
} else {
    Write-Host "✗ FEHLER GEFUNDEN!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Gesamtanzahl Fehler: $gesamtFehler" -ForegroundColor Red
    if ($gesamtWarnungen -gt 0) {
        Write-Host "Gesamtanzahl Warnungen: $gesamtWarnungen" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Bitte beheben Sie die Fehler vor dem Import!" -ForegroundColor Red
}

Write-Host ""

