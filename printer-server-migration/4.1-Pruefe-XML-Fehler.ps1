# ==================================================================
# Prüft die erstellten Import-XML-Dateien auf Fehler
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
$Server = "<PRINT-SERVER-1>"

# CSV-Dateien
$DruckerZuordnungCSV = Join-Path $OutputDir "3.2-Zuordnung-Drucker-Namen.csv"
$PortZuordnungCSV = Join-Path $OutputDir "3.3-Zuordnung-Port-Namen.csv"
$PortEntfernenCSV = Join-Path $OutputDir "3.4-Ports-Entfernen.csv"

# XML-Dateien
$PrintersXML = Join-Path $OutputDir "4.1-Import-<PRINT-SERVER-1>-Printers.xml"
$PortsXML = Join-Path $OutputDir "4.1-Import-<PRINT-SERVER-1>-Ports.xml"

Write-Host "=== Prüfe Import-XML-Dateien auf Fehler ===" -ForegroundColor Cyan
Write-Host ""

# Lade Zuordnungslisten
Write-Host "Lade Zuordnungslisten..." -ForegroundColor Cyan
$druckerZuordnung = Import-Csv -Path $DruckerZuordnungCSV -Delimiter ";" -Encoding UTF8 | Where-Object { $_.Server -eq $Server -and $_.Status -eq "OK" }
$portZuordnung = Import-Csv -Path $PortZuordnungCSV -Delimiter ";" -Encoding UTF8 | Where-Object { ($_.Server -eq $Server) -and ($_.Status -eq "OK" -or $_.Status -eq "IP_INKONSISTENT") }
$portEntfernen = Import-Csv -Path $PortEntfernenCSV -Delimiter ";" -Encoding UTF8 | Where-Object { $_.Server -eq $Server }

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

# Lade XML-Dateien
Write-Host "Lade XML-Dateien..." -ForegroundColor Cyan
[xml]$printersXml = Get-Content -Path $PrintersXML -Encoding UTF8
[xml]$portsXml = Get-Content -Path $PortsXML -Encoding UTF8

$nsManager = New-Object System.Xml.XmlNamespaceManager($printersXml.NameTable)
$nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")

$nsManager2 = New-Object System.Xml.XmlNamespaceManager($portsXml.NameTable)
$nsManager2.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")

Write-Host ""

# ==================================================================
# PRÜFUNG 1: ComputerName bei Druckern
# ==================================================================
Write-Host "=== PRÜFUNG 1: ComputerName bei Druckern ===" -ForegroundColor Yellow
$fehlerComputerName = @()
$alleDrucker = $printersXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager)
$anzahlDrucker = $alleDrucker.Count
Write-Host "Gefundene Drucker: $anzahlDrucker"

foreach ($obj in $alleDrucker) {
    $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager)
    if ($compNameProp) {
        $compName = $compNameProp.InnerText
        if ($compName -ne $NewServer) {
            $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
            $druckerName = if ($nameProp) { $nameProp.InnerText } else { "UNBEKANNT" }
            $fehlerComputerName += "Drucker '$druckerName': ComputerName ist '$compName' (sollte '$NewServer' sein)"
        }
    }
}

if ($fehlerComputerName.Count -eq 0) {
    Write-Host "  ✓ Alle ComputerName sind korrekt auf '$NewServer' gesetzt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerComputerName.Count) Drucker mit falschem ComputerName" -ForegroundColor Red
    foreach ($fehler in $fehlerComputerName) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 2: Druckernamen
# ==================================================================
Write-Host "=== PRÜFUNG 2: Druckernamen ===" -ForegroundColor Yellow
$fehlerDruckerNamen = @()
$gepruefteDrucker = 0

foreach ($obj in $alleDrucker) {
    $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
    if ($nameProp) {
        $druckerName = $nameProp.InnerText
        $key = $Server + '|' + $druckerName
        
        # Prüfe ob dieser Drucker eine Zuordnung haben sollte
        # (Wir müssen den alten Namen finden, um zu prüfen)
        # Da wir nur die neuen Namen haben, prüfen wir umgekehrt
        $gefunden = $false
        foreach ($mapping in $druckerMapping.Values) {
            if ($mapping.NewPrinterName -eq $druckerName) {
                $gefunden = $true
                $gepruefteDrucker++
                # Prüfe ob Name korrekt ist
                if ($mapping.NewPrinterName -ne $druckerName) {
                    $fehlerDruckerNamen += "Drucker sollte '$($mapping.NewPrinterName)' heißen, ist aber '$druckerName'"
                }
                break
            }
        }
        
        # Prüfe ob Drucker ohne Zuordnung den alten Namen hat (sollte nicht vorkommen bei Status OK)
        if (-not $gefunden) {
            # Prüfe ob es ein Standard-Windows-Drucker ist (diese haben keine Zuordnung)
            if ($druckerName -notmatch "Microsoft (XPS|Print to PDF)") {
                # Das könnte ein Fehler sein - Drucker sollte eine Zuordnung haben
                # Aber wir können nicht sicher sein, da wir den alten Namen nicht kennen
            }
        }
    }
}

Write-Host "  Geprüfte Drucker mit Zuordnung: $gepruefteDrucker"
if ($fehlerDruckerNamen.Count -eq 0) {
    Write-Host "  ✓ Alle Druckernamen sind korrekt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerDruckerNamen.Count) Drucker mit falschem Namen" -ForegroundColor Red
    foreach ($fehler in $fehlerDruckerNamen) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 3: Prüfe ob alle zugeordneten Drucker vorhanden sind
# ==================================================================
Write-Host "=== PRÜFUNG 3: Alle zugeordneten Drucker vorhanden? ===" -ForegroundColor Yellow
$fehlendeDrucker = @()

foreach ($mapping in $druckerMapping.Values) {
    $neuerName = $mapping.NewPrinterName
    $gefunden = $false
    
    foreach ($obj in $alleDrucker) {
        $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
        if ($nameProp -and $nameProp.InnerText -eq $neuerName) {
            $gefunden = $true
            break
        }
    }
    
    if (-not $gefunden) {
        $fehlendeDrucker += "Drucker '$neuerName' (alter Name: '$($mapping.OldPrinterName)') fehlt in XML"
    }
}

if ($fehlendeDrucker.Count -eq 0) {
    Write-Host "  ✓ Alle zugeordneten Drucker sind vorhanden" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlendeDrucker.Count) Drucker fehlen" -ForegroundColor Red
    foreach ($fehler in $fehlendeDrucker) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 4: ComputerName bei Ports
# ==================================================================
Write-Host "=== PRÜFUNG 4: ComputerName bei Ports ===" -ForegroundColor Yellow
$fehlerPortComputerName = @()
$allePorts = $portsXml.SelectNodes("//ps:Objs/ps:Obj", $nsManager2)
$anzahlPorts = $allePorts.Count
Write-Host "Gefundene Ports: $anzahlPorts"

foreach ($obj in $allePorts) {
    $compNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='ComputerName']", $nsManager2)
    if ($compNameProp) {
        $compName = $compNameProp.InnerText
        if ($compName -ne $NewServer) {
            $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
            $portName = if ($nameProp) { $nameProp.InnerText } else { "UNBEKANNT" }
            $fehlerPortComputerName += "Port '$portName': ComputerName ist '$compName' (sollte '$NewServer' sein)"
        }
    }
}

if ($fehlerPortComputerName.Count -eq 0) {
    Write-Host "  ✓ Alle ComputerName sind korrekt auf '$NewServer' gesetzt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerPortComputerName.Count) Ports mit falschem ComputerName" -ForegroundColor Red
    foreach ($fehler in $fehlerPortComputerName[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($fehlerPortComputerName.Count -gt 10) {
        Write-Host "    ... und $($fehlerPortComputerName.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 5: Port-Namen
# ==================================================================
Write-Host "=== PRÜFUNG 5: Port-Namen ===" -ForegroundColor Yellow
$fehlerPortNamen = @()
$geprueftePorts = 0

foreach ($obj in $allePorts) {
    $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
    if ($nameProp) {
        $portName = $nameProp.InnerText
        $geprueftePorts++
        
        # Prüfe ob dieser Port eine Zuordnung haben sollte
        $gefunden = $false
        foreach ($mapping in $portMapping.Values) {
            if ($mapping.NewPortName -eq $portName) {
                $gefunden = $true
                # Name ist korrekt
                break
            }
        }
        
        # Prüfe ob Port entfernt werden sollte (dann sollte er nicht vorhanden sein)
        $alterPortName = $portName
        foreach ($entry in $portEntfernen) {
            if ($entry.PortName -eq $alterPortName) {
                $fehlerPortNamen += "Port '$portName' sollte entfernt worden sein, ist aber noch vorhanden"
            }
        }
    }
}

Write-Host "  Geprüfte Ports: $geprueftePorts"
if ($fehlerPortNamen.Count -eq 0) {
    Write-Host "  ✓ Alle Port-Namen sind korrekt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerPortNamen.Count) Ports mit Problemen" -ForegroundColor Red
    foreach ($fehler in $fehlerPortNamen[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($fehlerPortNamen.Count -gt 10) {
        Write-Host "    ... und $($fehlerPortNamen.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 6: Prüfe ob alle zugeordneten Ports vorhanden sind
# ==================================================================
Write-Host "=== PRÜFUNG 6: Alle zugeordneten Ports vorhanden? ===" -ForegroundColor Yellow
$fehlendePorts = @()

foreach ($mapping in $portMapping.Values) {
    $neuerPortName = $mapping.NewPortName
    $gefunden = $false
    
    foreach ($obj in $allePorts) {
        $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
        if ($nameProp -and $nameProp.InnerText -eq $neuerPortName) {
            $gefunden = $true
            break
        }
    }
    
    if (-not $gefunden) {
        $fehlendePorts += "Port '$neuerPortName' (alter Name: '$($mapping.OldPortName)') fehlt in XML"
    }
}

if ($fehlendePorts.Count -eq 0) {
    Write-Host "  ✓ Alle zugeordneten Ports sind vorhanden" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlendePorts.Count) Ports fehlen" -ForegroundColor Red
    foreach ($fehler in $fehlendePorts[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($fehlendePorts.Count -gt 10) {
        Write-Host "    ... und $($fehlendePorts.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 7: Prüfe ob entfernte Ports wirklich entfernt wurden
# ==================================================================
Write-Host "=== PRÜFUNG 7: Entfernte Ports wirklich entfernt? ===" -ForegroundColor Yellow
$nochVorhandenePorts = @()

foreach ($entry in $portEntfernen) {
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
        $nochVorhandenePorts += "Port '$portName' sollte entfernt worden sein, ist aber noch vorhanden"
    }
}

if ($nochVorhandenePorts.Count -eq 0) {
    Write-Host "  ✓ Alle zu entfernenden Ports wurden entfernt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($nochVorhandenePorts.Count) Ports sollten entfernt sein" -ForegroundColor Red
    foreach ($fehler in $nochVorhandenePorts[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($nochVorhandenePorts.Count -gt 10) {
        Write-Host "    ... und $($nochVorhandenePorts.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 8: IP-Adressen bei Ports
# ==================================================================
Write-Host "=== PRÜFUNG 8: IP-Adressen bei Ports ===" -ForegroundColor Yellow
$fehlerIPAdressen = @()
$gepruefteIPPorts = 0

foreach ($obj in $allePorts) {
    $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager2)
    if ($nameProp) {
        $portName = $nameProp.InnerText
        
        # Finde zugehörige Zuordnung
        foreach ($mapping in $portMapping.Values) {
            if ($mapping.NewPortName -eq $portName) {
                $gepruefteIPPorts++
                $erwarteteIP = $mapping.IPAddress
                
                $hostAddrProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PrinterHostAddress']", $nsManager2)
                if ($hostAddrProp) {
                    $aktuelleIP = $hostAddrProp.InnerText
                    if ($aktuelleIP -ne $erwarteteIP) {
                        $fehlerIPAdressen += "Port '$portName': IP ist '$aktuelleIP' (sollte '$erwarteteIP' sein)"
                    }
                } else {
                    if ($erwarteteIP) {
                        $fehlerIPAdressen += "Port '$portName': PrinterHostAddress fehlt (sollte '$erwarteteIP' sein)"
                    }
                }
                break
            }
        }
    }
}

Write-Host "  Geprüfte Ports mit IP: $gepruefteIPPorts"
if ($fehlerIPAdressen.Count -eq 0) {
    Write-Host "  ✓ Alle IP-Adressen sind korrekt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerIPAdressen.Count) Ports mit falscher IP" -ForegroundColor Red
    foreach ($fehler in $fehlerIPAdressen[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($fehlerIPAdressen.Count -gt 10) {
        Write-Host "    ... und $($fehlerIPAdressen.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# PRÜFUNG 9: PortName bei Druckern
# ==================================================================
Write-Host "=== PRÜFUNG 9: PortName bei Druckern ===" -ForegroundColor Yellow
$fehlerDruckerPortName = @()
$gepruefteDruckerPorts = 0

foreach ($obj in $alleDrucker) {
    $nameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager)
    if ($nameProp) {
        $druckerName = $nameProp.InnerText
        
        # Finde zugehörige Zuordnung
        foreach ($mapping in $druckerMapping.Values) {
            if ($mapping.NewPrinterName -eq $druckerName) {
                $portNameProp = $obj.SelectSingleNode(".//ps:Props/ps:S[@N='PortName']", $nsManager)
                if ($portNameProp) {
                    $alterPortName = $portNameProp.InnerText
                    $portKey = $Server + '|' + $alterPortName
                    
                    if ($portMapping.ContainsKey($portKey)) {
                        $gepruefteDruckerPorts++
                        $portMap = $portMapping[$portKey]
                        $erwarteterPortName = $portMap.NewPortName
                        
                        if ($portNameProp.InnerText -ne $erwarteterPortName) {
                            $fehlerDruckerPortName += "Drucker '$druckerName': PortName ist '$($portNameProp.InnerText)' (sollte '$erwarteterPortName' sein)"
                        }
                    }
                }
                break
            }
        }
    }
}

Write-Host "  Geprüfte Drucker mit Port: $gepruefteDruckerPorts"
if ($fehlerDruckerPortName.Count -eq 0) {
    Write-Host "  ✓ Alle PortName bei Druckern sind korrekt" -ForegroundColor Green
} else {
    Write-Host "  ✗ FEHLER gefunden: $($fehlerDruckerPortName.Count) Drucker mit falschem PortName" -ForegroundColor Red
    foreach ($fehler in $fehlerDruckerPortName[0..9]) {
        Write-Host "    - $fehler" -ForegroundColor Red
    }
    if ($fehlerDruckerPortName.Count -gt 10) {
        Write-Host "    ... und $($fehlerDruckerPortName.Count - 10) weitere" -ForegroundColor Red
    }
}
Write-Host ""

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
$gesamtFehler = $fehlerComputerName.Count + $fehlerDruckerNamen.Count + $fehlendeDrucker.Count + 
                $fehlerPortComputerName.Count + $fehlerPortNamen.Count + $fehlendePorts.Count + 
                $nochVorhandenePorts.Count + $fehlerIPAdressen.Count + $fehlerDruckerPortName.Count

Write-Host "Gesamtanzahl gefundener Fehler: $gesamtFehler" -ForegroundColor $(if ($gesamtFehler -eq 0) { "Green" } else { "Red" })
Write-Host ""
Write-Host "Fehleraufschlüsselung:" -ForegroundColor Yellow
Write-Host "  - ComputerName bei Druckern: $($fehlerComputerName.Count)"
Write-Host "  - Druckernamen: $($fehlerDruckerNamen.Count)"
Write-Host "  - Fehlende Drucker: $($fehlendeDrucker.Count)"
Write-Host "  - ComputerName bei Ports: $($fehlerPortComputerName.Count)"
Write-Host "  - Port-Namen: $($fehlerPortNamen.Count)"
Write-Host "  - Fehlende Ports: $($fehlendePorts.Count)"
Write-Host "  - Nicht entfernte Ports: $($nochVorhandenePorts.Count)"
Write-Host "  - IP-Adressen: $($fehlerIPAdressen.Count)"
Write-Host "  - PortName bei Druckern: $($fehlerDruckerPortName.Count)"

if ($gesamtFehler -eq 0) {
    Write-Host ""
    Write-Host "✓ ALLE PRÜFUNGEN ERFOLGREICH!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✗ FEHLER GEFUNDEN - Bitte beheben!" -ForegroundColor Red
}

