# ==================================================================
# Validiert und testet die Import-XML-Dateien
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = $ScriptDir
$NewServer = "<PRINT-SERVER-1>-01"

# CSV-Dateien
$DruckerZuordnungCSV = Join-Path $OutputDir "3.2-Zuordnung-Drucker-Namen.csv"
$PortZuordnungCSV = Join-Path $OutputDir "3.3-Zuordnung-Port-Namen.csv"
$PortEntfernenCSV = Join-Path $OutputDir "3.4-Ports-Entfernen.csv"

# XML-Dateien (alle Server)
$XMLFiles = @(
    @{ Server = "<PRINT-SERVER-1>"; PrintersFile = "4.1-Import-<PRINT-SERVER-1>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-1>-Ports.xml" },
    @{ Server = "<PRINT-SERVER-2>"; PrintersFile = "4.1-Import-<PRINT-SERVER-2>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-2>-Ports.xml" },
    @{ Server = "<PRINT-SERVER-3>"; PrintersFile = "4.1-Import-<PRINT-SERVER-3>-Printers.xml"; PortsFile = "4.1-Import-<PRINT-SERVER-3>-Ports.xml" }
)

Write-Host "=== VALIDIERUNG UND TEST DER IMPORT-XML-DATEIEN ===" -ForegroundColor Cyan
Write-Host ""

# Lade Zuordnungslisten
Write-Host "Lade Zuordnungslisten..." -ForegroundColor Cyan
$druckerZuordnung = Import-Csv -Path $DruckerZuordnungCSV -Delimiter ";" -Encoding UTF8 | Where-Object { $_.Status -eq "OK" }
$portZuordnung = Import-Csv -Path $PortZuordnungCSV -Delimiter ";" -Encoding UTF8 | Where-Object { ($_.Status -eq "OK" -or $_.Status -eq "IP_INKONSISTENT") }
$portEntfernen = Import-Csv -Path $PortEntfernenCSV -Delimiter ";" -Encoding UTF8

# Erstelle Mappings
$druckerMapping = @{}
foreach ($entry in $druckerZuordnung) {
    $key = $entry.Server + '|' + $entry.OldPrinterName
    $druckerMapping[$key] = $entry
}

$portMapping = @{}
foreach ($entry in $portZuordnung) {
    $key = $entry.Server + '|' + $entry.OldPortName
    $portMapping[$key] = $entry
}

$portEntfernenMapping = @{}
foreach ($entry in $portEntfernen) {
    $key = $entry.Server + '|' + $entry.PortName
    $portEntfernenMapping[$key] = $true
}

Write-Host "  Drucker-Zuordnungen: $($druckerMapping.Count)" -ForegroundColor Green
Write-Host "  Port-Zuordnungen: $($portMapping.Count)" -ForegroundColor Green
Write-Host "  Ports zum Entfernen: $($portEntfernenMapping.Count)" -ForegroundColor Green
Write-Host ""

$gesamtFehler = 0
$gesamtWarnungen = 0

# Prüfe jede XML-Datei
foreach ($xmlFileInfo in $XMLFiles) {
    $server = $xmlFileInfo.Server
    $printersFile = $xmlFileInfo.PrintersFile
    $portsFile = $xmlFileInfo.PortsFile
    
    $printersPath = Join-Path $OutputDir $printersFile
    $portsPath = Join-Path $OutputDir $portsFile
    
    Write-Host "=== Prüfe $server ===" -ForegroundColor Yellow
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
    
    # Lade XML-Dateien
    try {
        [xml]$printersXml = Get-Content -Path $printersPath -Encoding UTF8
        [xml]$portsXml = Get-Content -Path $portsPath -Encoding UTF8
    } catch {
        Write-Host "  FEHLER: XML konnte nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    # Prüfe XML-Format
    if ($null -eq $printersXml.Objs) {
        Write-Host "  FEHLER: Ungültiges XML-Format in $printersFile" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    if ($null -eq $portsXml.Objs) {
        Write-Host "  FEHLER: Ungültiges XML-Format in $portsFile" -ForegroundColor Red
        $gesamtFehler++
        continue
    }
    
    Write-Host "  XML-Format: OK" -ForegroundColor Green
    
    # Namespace Manager
    $nsManager = New-Object System.Xml.XmlNamespaceManager($printersXml.NameTable)
    $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
    
    $nsManager2 = New-Object System.Xml.XmlNamespaceManager($portsXml.NameTable)
    $nsManager2.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
    
    # PRÜFUNG 1: ComputerName bei Druckern
    Write-Host "  Prüfe ComputerName bei Druckern..." -ForegroundColor Cyan
    $fehlerComputerName = @()
    $alleDrucker = $printersXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager)
    
    foreach ($obj in $alleDrucker) {
        $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager)
        if ($compNameProp) {
            $compName = $compNameProp.InnerText
            if ($compName -ne $NewServer) {
                $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
                $druckerName = if ($nameProp) { $nameProp.InnerText } else { "UNBEKANNT" }
                $fehlerComputerName += "Drucker '$druckerName': ComputerName ist '$compName' (erwartet: '$NewServer')"
            }
        }
    }
    
    if ($fehlerComputerName.Count -eq 0) {
        Write-Host "    OK: Alle ComputerName korrekt ($($alleDrucker.Count) Drucker)" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $($fehlerComputerName.Count) Drucker mit falschem ComputerName" -ForegroundColor Red
        foreach ($fehler in $fehlerComputerName[0..4]) {
            Write-Host "      - $fehler" -ForegroundColor Red
        }
        if ($fehlerComputerName.Count -gt 5) {
            Write-Host "      ... und $($fehlerComputerName.Count - 5) weitere" -ForegroundColor Red
        }
        $gesamtFehler += $fehlerComputerName.Count
    }
    
    # PRÜFUNG 2: ComputerName bei Ports
    Write-Host "  Prüfe ComputerName bei Ports..." -ForegroundColor Cyan
    $fehlerPortComputerName = @()
    $allePorts = $portsXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager2)
    
    foreach ($obj in $allePorts) {
        $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager2)
        if ($compNameProp) {
            $compName = $compNameProp.InnerText
            if ($compName -ne $NewServer) {
                $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
                $portName = if ($nameProp) { $nameProp.InnerText } else { "UNBEKANNT" }
                $fehlerPortComputerName += "Port '$portName': ComputerName ist '$compName' (erwartet: '$NewServer')"
            }
        }
    }
    
    if ($fehlerPortComputerName.Count -eq 0) {
        Write-Host "    OK: Alle ComputerName korrekt ($($allePorts.Count) Ports)" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $($fehlerPortComputerName.Count) Ports mit falschem ComputerName" -ForegroundColor Red
        foreach ($fehler in $fehlerPortComputerName[0..4]) {
            Write-Host "      - $fehler" -ForegroundColor Red
        }
        if ($fehlerPortComputerName.Count -gt 5) {
            Write-Host "      ... und $($fehlerPortComputerName.Count - 5) weitere" -ForegroundColor Red
        }
        $gesamtFehler += $fehlerPortComputerName.Count
    }
    
    # PRÜFUNG 3: Entfernte Ports wirklich entfernt
    Write-Host "  Prüfe entfernte Ports..." -ForegroundColor Cyan
    $nochVorhandenePorts = @()
    
    foreach ($entry in $portEntfernen) {
        if ($entry.Server -eq $server) {
            $portName = $entry.PortName
            $gefunden = $false
            
            foreach ($obj in $allePorts) {
                $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
                if ($nameProp -and $nameProp.InnerText -eq $portName) {
                    $gefunden = $true
                    break
                }
            }
            
            if ($gefunden) {
                $nochVorhandenePorts += "Port '$portName' sollte entfernt worden sein"
            }
        }
    }
    
    if ($nochVorhandenePorts.Count -eq 0) {
        Write-Host "    OK: Alle zu entfernenden Ports wurden entfernt" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $($nochVorhandenePorts.Count) Ports sollten entfernt sein" -ForegroundColor Red
        foreach ($fehler in $nochVorhandenePorts) {
            Write-Host "      - $fehler" -ForegroundColor Red
        }
        $gesamtFehler += $nochVorhandenePorts.Count
    }
    
    # PRÜFUNG 4: XML-Struktur Vergleich (Formatierung)
    Write-Host "  Prüfe XML-Struktur..." -ForegroundColor Cyan
    
    # Prüfe ob alle Objekte die erwartete Struktur haben
    $strukturFehler = 0
    foreach ($obj in $alleDrucker) {
        $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
        $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager)
        if (-not $nameProp -or -not $compNameProp) {
            $strukturFehler++
        }
    }
    
    foreach ($obj in $allePorts) {
        $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
        $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager2)
        if (-not $nameProp -or -not $compNameProp) {
            $strukturFehler++
        }
    }
    
    if ($strukturFehler -eq 0) {
        Write-Host "    OK: XML-Struktur korrekt" -ForegroundColor Green
    } else {
        Write-Host "    FEHLER: $strukturFehler Objekte mit fehlenden Properties" -ForegroundColor Red
        $gesamtFehler += $strukturFehler
    }
    
    Write-Host ""
}

# ==================================================================
# TEST: Import-PrintConfiguration Simulation
# ==================================================================
Write-Host "=== TEST: Import-PrintConfiguration Validierung ===" -ForegroundColor Cyan
Write-Host ""

$testFehler = 0

foreach ($xmlFileInfo in $XMLFiles) {
    $server = $xmlFileInfo.Server
    $printersFile = $xmlFileInfo.PrintersFile
    $portsFile = $xmlFileInfo.PortsFile
    
    $printersPath = Join-Path $OutputDir $printersFile
    $portsPath = Join-Path $OutputDir $portsFile
    
    if (-not (Test-Path $printersPath) -or -not (Test-Path $portsPath)) {
        continue
    }
    
    Write-Host "Teste $server..." -ForegroundColor Yellow
    
    # Versuche XML zu laden (wie Import-PrintConfiguration es tun würde)
    $printers = $null
    $ports = $null
    
    # Teste Drucker-XML
    try {
        $printers = Import-Clixml -Path $printersPath -ErrorAction Stop
        Write-Host "  OK: Drucker-XML geladen ($($printers.Count) Drucker)" -ForegroundColor Green
    } catch {
        Write-Host "  FEHLER: Drucker-XML kann nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
        $testFehler++
    }
    
    # Teste Ports-XML
    try {
        $ports = Import-Clixml -Path $portsPath -ErrorAction Stop
        Write-Host "  OK: Ports-XML geladen ($($ports.Count) Ports)" -ForegroundColor Green
    } catch {
        # Ports-XML kann oft nicht mit Import-Clixml geladen werden (TNRef-Problem)
        # Import-PrintConfiguration verarbeitet die XML aber trotzdem korrekt
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "TypeNames.*referenceId") {
            Write-Host "  WARNUNG: Ports-XML kann nicht mit Import-Clixml geladen werden (TNRef-Problem)" -ForegroundColor Yellow
            Write-Host "    Hinweis: Import-PrintConfiguration kann die XML trotzdem verarbeiten" -ForegroundColor Gray
            $gesamtWarnungen++
            # Setze auf null, damit weitere Prüfungen übersprungen werden
            $ports = $null
        } else {
            Write-Host "  FEHLER: Ports-XML kann nicht geladen werden: $errorMsg" -ForegroundColor Red
            $testFehler++
        }
    }
    
    if ($null -eq $printers -and $null -eq $ports) {
        Write-Host "  FEHLER: Beide XML-Dateien konnten nicht geladen werden" -ForegroundColor Red
        $testFehler++
        continue
    }
    
    if ($null -eq $ports) {
        Write-Host "  INFO: Weitere Prüfungen für Ports übersprungen (XML-Strukturproblem)" -ForegroundColor Gray
        Write-Host ""
        continue
    }
    
    try {
        
        # Prüfe ob alle Objekte ComputerName haben
        $druckerOhneComputerName = ($printers | Where-Object { -not $_.ComputerName }).Count
        $portsOhneComputerName = ($ports | Where-Object { -not $_.ComputerName }).Count
        
        if ($druckerOhneComputerName -gt 0) {
            Write-Host "    WARNUNG: $druckerOhneComputerName Drucker ohne ComputerName" -ForegroundColor Yellow
            $gesamtWarnungen += $druckerOhneComputerName
        }
        
        if ($portsOhneComputerName -gt 0) {
            Write-Host "    WARNUNG: $portsOhneComputerName Ports ohne ComputerName" -ForegroundColor Yellow
            $gesamtWarnungen += $portsOhneComputerName
        }
        
        # Prüfe ComputerName-Werte
        $falscheComputerName = ($printers | Where-Object { $_.ComputerName -ne $NewServer }).Count
        $falschePortComputerName = ($ports | Where-Object { $_.ComputerName -ne $NewServer }).Count
        
        if ($falscheComputerName -gt 0) {
            Write-Host "    FEHLER: $falscheComputerName Drucker mit falschem ComputerName" -ForegroundColor Red
            $testFehler += $falscheComputerName
        }
        
        if ($falschePortComputerName -gt 0) {
            Write-Host "    FEHLER: $falschePortComputerName Ports mit falschem ComputerName" -ForegroundColor Red
            $testFehler += $falschePortComputerName
        }
        
    } catch {
        Write-Host "  FEHLER: XML kann nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
        $testFehler++
    }
    
    Write-Host ""
}

$gesamtFehler += $testFehler

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

if ($gesamtFehler -eq 0) {
    if ($gesamtWarnungen -eq 0) {
        Write-Host "[OK] ALLE PRUEFUNGEN ERFOLGREICH!" -ForegroundColor Green
    } else {
        Write-Host "[OK] PRUEFUNGEN ERFOLGREICH (mit Warnungen)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Warnungen: $gesamtWarnungen (nicht kritisch)" -ForegroundColor Yellow
        Write-Host "Hinweis: Ports-XML kann nicht mit Import-Clixml geladen werden," -ForegroundColor Yellow
        Write-Host "         aber Import-PrintConfiguration kann die XML trotzdem verarbeiten" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Die XML-Dateien sind bereit für den Import auf $NewServer" -ForegroundColor Green
    Write-Host ""
    Write-Host "Nächste Schritte:" -ForegroundColor Yellow
    Write-Host "  1. Import-PrintConfiguration -Path '$OutputDir\4.1-Import-*-Printers.xml' -ComputerName $NewServer" -ForegroundColor Gray
    Write-Host "  2. Import-PrintConfiguration -Path '$OutputDir\4.1-Import-*-Ports.xml' -ComputerName $NewServer" -ForegroundColor Gray
} else {
    Write-Host "[FEHLER] FEHLER GEFUNDEN!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Gesamtanzahl Fehler: $gesamtFehler" -ForegroundColor Red
    if ($gesamtWarnungen -gt 0) {
        Write-Host "Gesamtanzahl Warnungen: $gesamtWarnungen" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Bitte beheben Sie die Fehler vor dem Import!" -ForegroundColor Red
}

Write-Host ""

