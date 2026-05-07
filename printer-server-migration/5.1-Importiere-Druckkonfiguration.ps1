# ==================================================================
# Importiert die angepassten XML-Dateien auf den Printserver
# ==================================================================
# 
# Dieses Script importiert die erstellten Import-XML-Dateien Schritt für Schritt
# und fragt nach jedem Import, ob fortgefahren werden soll.
#
# WICHTIG: Führen Sie dieses Script auf dem Zielserver (<PRINT-SERVER-1>-01) aus
#          oder verwenden Sie -ComputerName Parameter
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [bool]$SkipConfirmation = $true
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
$ImportLogFile = Join-Path $LogDir "5.1-Importiere-Druckkonfiguration_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
$ImportedPrintersFile = Join-Path $LogDir "5.1-Imported-Printers_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"

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
    Add-Content -Path $ImportLogFile -Value $logMessage -Encoding UTF8
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# Funktion zum Erstellen eines Ports mit Timeout
function Add-PrinterPortWithTimeout {
    param(
        [string]$Name,
        [string]$PrinterHostAddress,
        [int]$PortNumber = 9100,
        [string]$ComputerName = $null,
        [int]$TimeoutSeconds = 10
    )
    
    $scriptBlock = {
        param($PortName, $IP, $Port, $Server)
        
        if ($Server) {
            Add-PrinterPort -Name $PortName -ComputerName $Server -PrinterHostAddress $IP -PortNumber $Port -ErrorAction Stop
        } else {
            Add-PrinterPort -Name $PortName -PrinterHostAddress $IP -PortNumber $Port -ErrorAction Stop
        }
    }
    
    try {
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $Name, $PrinterHostAddress, $PortNumber, $ComputerName
        $result = Wait-Job -Job $job -Timeout $TimeoutSeconds
        
        if ($result) {
            Receive-Job -Job $job | Out-Null
            Remove-Job -Job $job -Force
            return $true
        } else {
            # Timeout - Job abbrechen
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force
            throw "Timeout nach $TimeoutSeconds Sekunden"
        }
    } catch {
        throw $_.Exception.Message
    }
}

# Funktion zum Bereinigen von Share-Namen (entfernt nur ungültige Zeichen für Windows Share-Namen)
# Windows Share-Namen dürfen NICHT enthalten: < > : " / \ | ? * [ ] { } ( ) + = & % $ # @ ! ~ ` ^ . (Punkt)
# Erlaubt sind: a-z, A-Z, 0-9, Leerzeichen, Bindestriche (-), Unterstriche (_)
# Maximale Länge: 80 Zeichen
function Remove-InvalidShareCharacters {
    param([string]$ShareName)
    
    if ([string]::IsNullOrWhiteSpace($ShareName)) {
        return $ShareName
    }
    
    $cleaned = $ShareName
    
    # Ersetze Punkte durch Unterstriche (Punkte sind in Share-Namen nicht erlaubt)
    $cleaned = $cleaned -replace '\.', '_'
    
    # Entferne/Ersetze nur die wirklich nicht erlaubten Zeichen: < > : " / \ | ? * [ ] { } ( ) + = & % $ # @ ! ~ ` ^
    # Ersetze durch Unterstriche, damit der Name möglichst erhalten bleibt
    $cleaned = $cleaned -replace '[<>:"/\\|?*\[\]{}()+=&%$#@!~`^]', '_'
    
    # Entferne mehrfache Unterstriche (die durch Ersetzungen entstanden sind)
    $cleaned = $cleaned -replace '_+', '_'
    
    # Entferne führende/abschließende Unterstriche
    $cleaned = $cleaned.Trim('_')
    
    # Stelle sicher, dass der Name nicht leer ist
    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        $cleaned = "Printer_Share"
    }
    
    # Maximale Länge für Share-Namen: 80 Zeichen (Windows-Limit)
    if ($cleaned.Length -gt 80) {
        $cleaned = $cleaned.Substring(0, 80)
        $cleaned = $cleaned.Trim('_')
    }
    
    return $cleaned
}

# Funktion zum Bereinigen von Port-Namen (entfernt ungültige Zeichen und kürzt bei Bedarf)
function Remove-InvalidPortCharacters {
    param([string]$PortName)
    
    if ([string]::IsNullOrWhiteSpace($PortName)) {
        return $PortName
    }
    
    # Entferne ungültige Zeichen für Windows Printer Port-Namen
    # Klammern () sind nicht erlaubt
    # Andere problematische Zeichen: < > : " / \ | ? *
    $cleaned = $PortName -replace '[()<>:"/\\|?*]', ''
    
    # Entferne mehrfache Leerzeichen
    $cleaned = $cleaned -replace '\s+', ' '
    
    # Trim
    $cleaned = $cleaned.Trim()
    
    # WICHTIG: Port-Namen mit IP-Adresse haben ein Limit von ca. 60 Zeichen
    # Wenn der Port-Name mit einer IP-Adresse beginnt, entferne zuerst die Druckerbezeichnung
    if ($cleaned -match '^(\d+\.\d+\.\d+\.\d+)\s+(.+)$') {
        $ipAddress = $matches[1]
        $printerName = $matches[2]
        $ipLength = $ipAddress.Length
        
        # Entferne NUR die Hersteller-Modell-Bezeichnung (z.B. "BRO-MFC-J5335DW", "KYO-P6035cdn")
        # Modell besteht aus 1-3 Teilen mit nur Großbuchstaben/Zahlen
        # Pattern: -(BRO|KYO|KON|CAN|HP)- gefolgt von 1-3 Modell-Teilen
        # Modell endet wenn das nächste Wort mit Kleinbuchstaben beginnt (z.B. "Architektur", "TeamLtg", "Personalabteilung")
        # Verwende non-greedy matching (?=...) um nur bis zum nächsten Wort zu matchen
        $printerName = $printerName -replace '-(BRO|KYO|KON|CAN|HP)(-[A-Z0-9]+){1,3}?(?=-[A-Z][a-z])', ''
        $printerName = $printerName -replace '--+', '-'
        $printerName = $printerName.Trim('-')
        
        # Entferne auch "-SW" und "-COL" am Ende
        $printerName = $printerName -replace '-(SW|COL)$', ''
        $printerName = $printerName.Trim('-')
        
        $cleaned = "$ipAddress $printerName"
        
        # Falls immer noch über 60 Zeichen, kürze am Ende
        if ($cleaned.Length -gt 60) {
            $maxPrinterNameLength = 60 - $ipLength - 1  # -1 für das Leerzeichen
            if ($printerName.Length -gt $maxPrinterNameLength) {
                $printerName = $printerName.Substring(0, $maxPrinterNameLength)
            }
            $cleaned = "$ipAddress $printerName"
        }
    }
    
    return $cleaned
}

# Funktion zum automatischen Erstellen eines fehlenden Ports
function Create-MissingPrinterPort {
    param(
        [string]$PortName,
        [string]$ComputerName,
        [string[]]$PortsFiles
    )
    
    $useLocalhost = ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME)
    $portCreated = $false
    
    # Versuche Port in XML-Dateien zu finden
    $portFound = $null
    foreach ($portsFile in $PortsFiles) {
        try {
            [xml]$xmlDoc = Get-Content -Path $portsFile.FullName -Encoding UTF8 -ErrorAction Stop
            $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
            
            $portNodes = $xmlDoc.SelectNodes("//ps:Objs/ps:Obj", $nsManager)
            foreach ($portNode in $portNodes) {
                $xmlPortName = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager).InnerText
                $cleanedXmlPortName = Remove-InvalidPortCharacters -PortName $xmlPortName
                
                if ($cleanedXmlPortName -eq $PortName) {
                    # Port gefunden in XML
                    $portMonitor = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='PortMonitor']", $nsManager)
                    $portMonitor = if ($portMonitor) { $portMonitor.InnerText } else { "" }
                    
                    $hostAddress = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='PrinterHostAddress']", $nsManager)
                    $hostAddress = if ($hostAddress) { $hostAddress.InnerText } else { $null }
                    
                    $portNumber = $portNode.SelectSingleNode(".//ps:Props/ps:I32[@N='PortNumber']", $nsManager)
                    $portNumber = if ($portNumber) { [int]$portNumber.InnerText } else { 9100 }
                    
                    $portFound = [PSCustomObject]@{
                        Name = $xmlPortName
                        PortMonitor = $portMonitor
                        PrinterHostAddress = $hostAddress
                        PortNumber = $portNumber
                    }
                    break
                }
            }
            if ($portFound) { break }
        } catch {
            # Weiter mit nächster Datei
            continue
        }
    }
    
    # Erstelle Port basierend auf gefundenen Informationen oder Port-Namen
    try {
        if ($portFound -and $portFound.PrinterHostAddress) {
            # Port aus XML mit IP-Adresse
            Write-Log "  Erstelle fehlenden Port aus XML: $PortName ($($portFound.PrinterHostAddress))" "INFO"
            $portNum = if ($portFound.PortNumber) { $portFound.PortNumber } else { 9100 }
            $serverName = if ($useLocalhost) { $null } else { $ComputerName }
            Add-PrinterPortWithTimeout -Name $PortName -PrinterHostAddress $portFound.PrinterHostAddress -PortNumber $portNum -ComputerName $serverName -TimeoutSeconds 10
            $portCreated = $true
        } elseif ($PortName -match "^\d+\.\d+\.\d+\.\d+") {
            # Port-Name enthält IP-Adresse, extrahiere sie
            $ipAddress = $PortName -split " " | Select-Object -First 1
            Write-Log "  Erstelle fehlenden Port aus Name: $PortName ($ipAddress)" "INFO"
            $serverName = if ($useLocalhost) { $null } else { $ComputerName }
            Add-PrinterPortWithTimeout -Name $PortName -PrinterHostAddress $ipAddress -PortNumber 9100 -ComputerName $serverName -TimeoutSeconds 10
            $portCreated = $true
        } else {
            Write-Log "  WARNUNG: Kann Port '$PortName' nicht automatisch erstellen (keine IP-Adresse gefunden)" "WARNING"
        }
    } catch {
        # Falls Timeout-Funktion fehlschlägt, versuche direkt
        try {
            if ($portFound -and $portFound.PrinterHostAddress) {
                $portNum = if ($portFound.PortNumber) { $portFound.PortNumber } else { 9100 }
                if ($useLocalhost) {
                    Add-PrinterPort -Name $PortName -PrinterHostAddress $portFound.PrinterHostAddress -PortNumber $portNum -ErrorAction Stop
                } else {
                    Add-PrinterPort -Name $PortName -ComputerName $ComputerName -PrinterHostAddress $portFound.PrinterHostAddress -PortNumber $portNum -ErrorAction Stop
                }
                $portCreated = $true
            } elseif ($PortName -match "^\d+\.\d+\.\d+\.\d+") {
                $ipAddress = $PortName -split " " | Select-Object -First 1
                if ($useLocalhost) {
                    Add-PrinterPort -Name $PortName -PrinterHostAddress $ipAddress -PortNumber 9100 -ErrorAction Stop
                } else {
                    Add-PrinterPort -Name $PortName -ComputerName $ComputerName -PrinterHostAddress $ipAddress -PortNumber 9100 -ErrorAction Stop
                }
                $portCreated = $true
            }
        } catch {
            Write-Log "  FEHLER beim automatischen Erstellen von Port '$PortName': $($_.Exception.Message)" "ERROR"
        }
    }
    
    return $portCreated
}

# Prüfe ob PrintManagement Module verfügbar ist
Write-Log "Prüfe PrintManagement Module..." "INFO"
if (-not (Get-Module -ListAvailable -Name PrintManagement)) {
    Write-Log "FEHLER: PrintManagement Module nicht gefunden. Bitte installieren Sie es mit: Install-Module -Name PrintManagement" "ERROR"
    exit 1
}

# Lade PrintManagement Module
try {
    Import-Module PrintManagement -ErrorAction Stop
    Write-Log "PrintManagement Module geladen" "SUCCESS"
} catch {
    Write-Log "FEHLER: PrintManagement Module konnte nicht geladen werden: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Prüfe Verbindung zum Server
Write-Log "Prüfe Verbindung zu $ComputerName..." "INFO"
try {
    $connection = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
    if (-not $connection) {
        Write-Log "FEHLER: Keine Verbindung zu $ComputerName möglich" "ERROR"
        exit 1
    }
    Write-Log "Verbindung zu $ComputerName erfolgreich" "SUCCESS"
} catch {
    Write-Log "FEHLER: Verbindung fehlgeschlagen: $($_.Exception.Message)" "ERROR"
    exit 1
}

Write-Host ""
Write-Host "=== IMPORT DER PRINT-KONFIGURATION ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host "Log-Datei: $ImportLogFile" -ForegroundColor Gray
Write-Host ""

# Finde alle Import-XML-Dateien
$printersFiles = Get-ChildItem -Path $OutputDir -Filter "4.1-Import-*-Printers.xml" | Sort-Object Name
$portsFiles = Get-ChildItem -Path $OutputDir -Filter "4.1-Import-*-Ports.xml" | Sort-Object Name

if ($printersFiles.Count -eq 0 -and $portsFiles.Count -eq 0) {
    Write-Log "FEHLER: Keine Import-XML-Dateien gefunden in $OutputDir" "ERROR"
    exit 1
}

Write-Log "Gefundene Dateien:" "INFO"
Write-Log "  - Drucker-XML: $($printersFiles.Count) Dateien" "INFO"
Write-Log "  - Ports-XML: $($portsFiles.Count) Dateien" "INFO"
Write-Host ""

# Liste der importierten Drucker (für Fallback)
$importedPrinters = @()

# Zähler für geteilte Drucker
$sharedPrintersCount = 0
$notSharedPrintersCount = 0

# ==================================================================
# IMPORT: Ports zuerst (Drucker benötigen Ports)
# ==================================================================
Write-Host "=== IMPORT: PORTS ===" -ForegroundColor Cyan
Write-Host ""

$portImportCount = 0
$portErrorCount = 0

# Lade alle vorhandenen Ports einmalig in Hash-Table (für schnelle Prüfung)
Write-Host "Lade vorhandene Ports vom Server..." -ForegroundColor Yellow
Write-Log "Lade vorhandene Ports vom Server für schnelle Pruefung..." "INFO"
$existingPortsHash = @{}
try {
    $useLocalhost = ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME)
    $allExistingPorts = if ($useLocalhost) {
        Get-PrinterPort -ErrorAction SilentlyContinue
    } else {
        Get-PrinterPort -ComputerName $ComputerName -ErrorAction SilentlyContinue
    }
    
    foreach ($existingPort in $allExistingPorts) {
        $portName = $existingPort.Name
        $normalized = ($portName -replace '\s+', '').ToLower()
        if (-not $existingPortsHash.ContainsKey($normalized)) {
            $existingPortsHash[$normalized] = @()
        }
        $existingPortsHash[$normalized] += $portName
    }
    Write-Host "  Gefunden: $($allExistingPorts.Count) vorhandene Ports" -ForegroundColor Green
    Write-Log "Gefunden: $($allExistingPorts.Count) vorhandene Ports" "INFO"
} catch {
    Write-Log "WARNUNG: Konnte vorhandene Ports nicht laden: $($_.Exception.Message). Pruefe jeden Port einzeln." "WARNING"
    Write-Host "  [WARNUNG] Konnte vorhandene Ports nicht laden, pruefe einzeln" -ForegroundColor Yellow
}

Write-Host ""

# Ports importieren
foreach ($portsFile in $portsFiles) {
    $filePath = $portsFile.FullName
    $fileName = $portsFile.Name
    
    Write-Host "Datei: $fileName" -ForegroundColor Yellow
    Write-Log "Importiere Ports aus: $fileName" "INFO"
    
    # Prüfe ob Datei existiert
    if (-not (Test-Path $filePath)) {
        Write-Log "FEHLER: Datei nicht gefunden: $filePath" "ERROR"
        $portErrorCount++
        continue
    }
    
    # Importiere Ports
    try {
        Write-Log "Lade Ports aus XML..." "INFO"
        $ports = $null
        
        # Versuche Import-Clixml
        try {
            $ports = Import-Clixml -Path $filePath -ErrorAction Stop
        } catch {
            # Falls Import-Clixml fehlschlägt (TNRef-Problem), parse XML manuell
            Write-Log "Import-Clixml fehlgeschlagen, parse XML manuell..." "WARNING"
            [xml]$xmlDoc = Get-Content -Path $filePath -Encoding UTF8
            $ports = @()
            
            $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $nsManager.AddNamespace("ps", "http://schemas.microsoft.com/powershell/2004/04")
            
            $portNodes = $xmlDoc.SelectNodes("//ps:Objs/ps:Obj", $nsManager)
            foreach ($portNode in $portNodes) {
                $portName = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='Name']", $nsManager).InnerText
                $portMonitor = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='PortMonitor']", $nsManager)
                $portMonitor = if ($portMonitor) { $portMonitor.InnerText } else { "" }
                
                # Nur TCP/IP Ports importieren (keine lokalen Ports)
                if ($portMonitor -eq "Standard TCP/IP Port" -or $portName -match "^\d+\.\d+\.\d+\.\d+") {
                    $portObj = [PSCustomObject]@{
                        Name = $portName
                        PortMonitor = $portMonitor
                    }
                    
                    # Versuche PrinterHostAddress zu extrahieren
                    $hostAddress = $portNode.SelectSingleNode(".//ps:Props/ps:S[@N='PrinterHostAddress']", $nsManager)
                    if ($hostAddress) {
                        $portObj | Add-Member -MemberType NoteProperty -Name "PrinterHostAddress" -Value $hostAddress.InnerText
                    }
                    
                    # Versuche PortNumber zu extrahieren
                    $portNumber = $portNode.SelectSingleNode(".//ps:Props/ps:I32[@N='PortNumber']", $nsManager)
                    if ($portNumber) {
                        $portObj | Add-Member -MemberType NoteProperty -Name "PortNumber" -Value [int]$portNumber.InnerText
                    }
                    
                    $ports += $portObj
                }
            }
        }
        
        if ($null -eq $ports -or $ports.Count -eq 0) {
            Write-Log "WARNUNG: Keine Ports in XML-Datei gefunden" "WARNING"
            Write-Host "  [INFO] Keine Ports in Datei" -ForegroundColor Gray
            $portImportCount++
            continue
        }
        
        # Konvertiere zu Array falls einzelnes Objekt
        if ($ports -isnot [Array]) {
            $ports = @($ports)
        }
        
        Write-Log "Gefunden: $($ports.Count) Ports zum Importieren" "INFO"
        $portSuccess = 0
        $portSkipped = 0
        
        foreach ($port in $ports) {
            try {
                $originalPortName = $port.Name
                
                # Überspringe lokale Ports (LPT, COM, FILE, PORTPROMPT)
                if ($originalPortName -match "^(LPT|COM|FILE|PORTPROMPT):") {
                    Write-Log "  Lokaler Port übersprungen: $originalPortName" "INFO"
                    $portSkipped++
                    continue
                }
                
                # Bereinige Port-Name (entferne ungültige Zeichen)
                $portName = Remove-InvalidPortCharacters -PortName $originalPortName
                
                if ($portName -ne $originalPortName) {
                    Write-Log "  Port-Name bereinigt: '$originalPortName' → '$portName'" "WARNING"
                }
                
                # Prüfe ob Port bereits existiert (schnelle Hash-Table-Prüfung)
                $normalizedPortName = ($portName -replace '\s+', '').ToLower()
                $portExists = $false
                
                if ($existingPortsHash.ContainsKey($normalizedPortName)) {
                    # Prüfe ob exakter Name vorhanden
                    foreach ($existingPortName in $existingPortsHash[$normalizedPortName]) {
                        if ($existingPortName -eq $portName) {
                            $portExists = $true
                            break
                        }
                    }
                }
                
                # Falls nicht in Hash-Table, prüfe einzeln (Fallback)
                if (-not $portExists) {
                    $existingPort = if ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME) {
                        Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
                    } else {
                        Get-PrinterPort -ComputerName $ComputerName -Name $portName -ErrorAction SilentlyContinue
                    }
                    if ($existingPort) {
                        $portExists = $true
                        # Füge zu Hash-Table hinzu für zukünftige Prüfungen
                        if (-not $existingPortsHash.ContainsKey($normalizedPortName)) {
                            $existingPortsHash[$normalizedPortName] = @()
                        }
                        $existingPortsHash[$normalizedPortName] += $portName
                    }
                }
                
                if ($portExists) {
                    Write-Log "  Port bereits vorhanden, überspringe: $portName" "INFO"
                    $portSkipped++
                    continue
                }
                
                # Erstelle Port basierend auf Typ (ohne ComputerName bei localhost)
                $useLocalhost = ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME)
                
                # SNMP-Tests deaktivieren, um Hänger zu vermeiden
                # Timeout für Port-Erstellung: 5 Sekunden
                $portCreated = $false
                
                if ($port.PrinterHostAddress) {
                    # TCP/IP Port
                    Write-Host "  [INFO] Erstelle Port: $portName ($($port.PrinterHostAddress))..." -ForegroundColor Gray
                    try {
                        $portNum = if ($port.PortNumber) { $port.PortNumber } else { 9100 }
                        $serverName = if ($useLocalhost) { $null } else { $ComputerName }
                        Add-PrinterPortWithTimeout -Name $portName -PrinterHostAddress $port.PrinterHostAddress -PortNumber $portNum -ComputerName $serverName -TimeoutSeconds 10
                        $portCreated = $true
                    } catch {
                        # Falls Timeout-Funktion fehlschlägt, versuche direkt (ohne SNMP)
                        try {
                            if ($useLocalhost) {
                                Add-PrinterPort -Name $portName -PrinterHostAddress $port.PrinterHostAddress -PortNumber $(if ($port.PortNumber) { $port.PortNumber } else { 9100 }) -ErrorAction Stop
                            } else {
                                Add-PrinterPort -Name $portName -ComputerName $ComputerName -PrinterHostAddress $port.PrinterHostAddress -PortNumber $(if ($port.PortNumber) { $port.PortNumber } else { 9100 }) -ErrorAction Stop
                            }
                            $portCreated = $true
                        } catch {
                            throw $_
                        }
                    }
                } elseif ($portName -match "^\d+\.\d+\.\d+\.\d+") {
                    # Port-Name enthält IP-Adresse
                    $ipAddress = $portName -split " " | Select-Object -First 1
                    Write-Host "  [INFO] Erstelle Port: $portName ($ipAddress)..." -ForegroundColor Gray
                    try {
                        $serverName = if ($useLocalhost) { $null } else { $ComputerName }
                        Add-PrinterPortWithTimeout -Name $portName -PrinterHostAddress $ipAddress -PortNumber 9100 -ComputerName $serverName -TimeoutSeconds 10
                        $portCreated = $true
                    } catch {
                        # Falls Timeout-Funktion fehlschlägt, versuche direkt
                        try {
                            if ($useLocalhost) {
                                Add-PrinterPort -Name $portName -PrinterHostAddress $ipAddress -PortNumber 9100 -ErrorAction Stop
                            } else {
                                Add-PrinterPort -Name $portName -ComputerName $ComputerName -PrinterHostAddress $ipAddress -PortNumber 9100 -ErrorAction Stop
                            }
                            $portCreated = $true
                        } catch {
                            throw $_
                        }
                    }
                } else {
                    Write-Log "  FEHLER: Unbekannter Port-Typ: $portName" "ERROR"
                    Write-Host "  [FEHLER] Unbekannter Port-Typ: $portName" -ForegroundColor Red
                    throw "Unbekannter Port-Typ: $portName"
                }
                
                if ($portCreated) {
                    Write-Log "  Port erstellt: $portName" "INFO"
                    Write-Host "  [OK] Port erstellt: $portName" -ForegroundColor Green
                    $portSuccess++
                }
            } catch {
                $errorMsg = "FEHLER beim Erstellen von Port '$portName' (Original: '$originalPortName'): $($_.Exception.Message)"
                Write-Log $errorMsg "ERROR"
                Write-Host "  [FEHLER] $errorMsg" -ForegroundColor Red
                $portErrorCount++
                # Weiter mit nächstem Port statt abzubrechen
                continue
            }
        }
        
        Write-Log "Ports importiert: $portSuccess erfolgreich, $portSkipped übersprungen" "SUCCESS"
        Write-Host "  [OK] Ports importiert: $portSuccess erfolgreich, $portSkipped übersprungen" -ForegroundColor Green
        $portImportCount++
        
    } catch {
        Write-Log "FEHLER beim Import der Ports: $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        $portErrorCount++
    }
    
    Write-Host ""
    
    # Frage ob fortgefahren werden soll (außer wenn SkipConfirmation gesetzt ist)
    if (-not $SkipConfirmation) {
        $continue = Read-Host "Möchten Sie mit der nächsten Datei fortfahren? (J/N)"
        if ($continue -notmatch "^[JjYy]") {
            Write-Log "Import abgebrochen vom Benutzer" "WARNING"
            Write-Host "Import abgebrochen." -ForegroundColor Yellow
            break
        }
        Write-Host ""
    }
} # Ende der Port-Import-Schleife

Write-Host ""

# ==================================================================
# IMPORT: Drucker
# ==================================================================
Write-Host "=== IMPORT: DRUCKER ===" -ForegroundColor Cyan
Write-Host ""

$printerImportCount = 0
$printerErrorCount = 0

foreach ($printersFile in $printersFiles) {
    $filePath = $printersFile.FullName
    $fileName = $printersFile.Name
    
    Write-Host "Datei: $fileName" -ForegroundColor Yellow
    Write-Log "Importiere Drucker aus: $fileName" "INFO"
    
    # Prüfe ob Datei existiert
    if (-not (Test-Path $filePath)) {
        Write-Log "FEHLER: Datei nicht gefunden: $filePath" "ERROR"
        $printerErrorCount++
        continue
    }
    
    # Importiere Drucker
    try {
        Write-Log "Lade Drucker aus XML..." "INFO"
        $printers = Import-Clixml -Path $filePath -ErrorAction Stop
        
        if ($null -eq $printers) {
            Write-Log "WARNUNG: Keine Drucker in XML-Datei gefunden" "WARNING"
            Write-Host "  [INFO] Keine Drucker in Datei" -ForegroundColor Gray
            $printerImportCount++
            continue
        }
        
        # Konvertiere zu Array falls einzelnes Objekt
        if ($printers -isnot [Array]) {
            $printers = @($printers)
        }
        
        Write-Log "Gefunden: $($printers.Count) Drucker zum Importieren" "INFO"
        $printerSuccess = 0
        $printerSkipped = 0
        
        foreach ($printer in $printers) {
        try {
                $printerName = $printer.Name
                
                # Prüfe ob Drucker bereits existiert (ohne ComputerName bei localhost)
                $existingPrinter = if ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME) {
                    Get-Printer -Name $printerName -ErrorAction SilentlyContinue
                } else {
                    Get-Printer -ComputerName $ComputerName -Name $printerName -ErrorAction SilentlyContinue
                }
                if ($existingPrinter) {
                    Write-Log "  Drucker bereits vorhanden, überspringe: $printerName" "INFO"
                    $printerSkipped++
                    continue
                }
                
                # Erstelle Drucker (ohne ComputerName bei localhost)
                $useLocalhost = ($ComputerName -eq "localhost" -or $ComputerName -eq $env:COMPUTERNAME)
                $printerParams = @{
                    Name = $printerName
                    ErrorAction = "Stop"
                }
                if (-not $useLocalhost) {
                    $printerParams["ComputerName"] = $ComputerName
                }
                
                # Port - bereinige Port-Namen (muss mit den beim Port-Import erstellten Namen übereinstimmen)
                if ($printer.PortName) {
                    $originalPortName = $printer.PortName
                    $cleanedPortName = Remove-InvalidPortCharacters -PortName $originalPortName
                    
                    if ($cleanedPortName -ne $originalPortName) {
                        Write-Log "  Port-Name für Drucker bereinigt: '$originalPortName' → '$cleanedPortName'" "WARNING"
                    }
                    
                    # Prüfe ob Port existiert (ohne ComputerName bei localhost)
                    $existingPort = if ($useLocalhost) {
                        Get-PrinterPort -Name $cleanedPortName -ErrorAction SilentlyContinue
                    } else {
                        Get-PrinterPort -ComputerName $ComputerName -Name $cleanedPortName -ErrorAction SilentlyContinue
                    }
                    if (-not $existingPort) {
                        Write-Log "  Port '$cleanedPortName' existiert nicht, erstelle automatisch..." "INFO"
                        $portCreated = Create-MissingPrinterPort -PortName $cleanedPortName -ComputerName $ComputerName -PortsFiles $portsFiles
                        if ($portCreated) {
                            Write-Log "  Port '$cleanedPortName' erfolgreich erstellt" "SUCCESS"
                            Write-Host "  [OK] Port automatisch erstellt: $cleanedPortName" -ForegroundColor Green
                        } else {
                            Write-Log "  WARNUNG: Port '$cleanedPortName' konnte nicht automatisch erstellt werden für Drucker '$printerName'" "WARNING"
                        }
                    }
                    
                    $printerParams["PortName"] = $cleanedPortName
                }
                
                # Driver
                if ($printer.DriverName) {
                    $printerParams["DriverName"] = $printer.DriverName
                } else {
                    Write-Log "  WARNUNG: Kein Treiber angegeben für $printerName, verwende Standard" "WARNING"
                }
                
                # Location und Comment können beim Erstellen gesetzt werden
                if ($printer.Location) {
                    $printerParams["Location"] = $printer.Location
                }
                
                if ($printer.Comment) {
                    $printerParams["Comment"] = $printer.Comment
                }
                
                # Erstelle Drucker ZUERST ohne Shared/ShareName (kann Probleme verursachen)
                Add-Printer @printerParams
                
                # WICHTIG: Alle Drucker müssen geteilt werden (außer Microsoft-Drucker)
                # Setze Shared und ShareName NACH dem Erstellen
                $shouldShare = $true
                
                # Microsoft-Drucker nicht teilen
                if ($printerName -like "Microsoft*" -or $printerName -like "*XPS*" -or $printerName -like "*PDF*") {
                    $shouldShare = $false
                }
                
                # Prüfe ob Shared-Eigenschaft in XML vorhanden ist
                if ($null -ne $printer.Shared) {
                    $shouldShare = $printer.Shared
                }
                
                # Setze Shared-Status
                if ($shouldShare) {
                    # WICHTIG: ShareName wird IMMER auf den Druckernamen gesetzt (nicht aus XML)
                    # Bereinige Share-Name: Entferne ungültige Zeichen für Windows Share-Namen
                    $shareNameToUse = Remove-InvalidShareCharacters -ShareName $printerName
                    
                    # Falls Share-Name nach Bereinigung leer ist, verwende einen Standard-Namen
                    if ([string]::IsNullOrWhiteSpace($shareNameToUse)) {
                        $shareNameToUse = "Printer_$($printerName.Substring(0, [Math]::Min(70, $printerName.Length)))"
                        $shareNameToUse = Remove-InvalidShareCharacters -ShareName $shareNameToUse
                    }
                    
                    # Debug: Zeige Original- und bereinigten Namen
                    Write-Log "  Share-Name bereinigt: '$printerName' → '$shareNameToUse'" "INFO"
                    
                    # Setze Shared mit ShareName (bereinigter Druckername)
                    try {
                        if ($useLocalhost) {
                            Set-Printer -Name $printerName -Shared $true -ShareName $shareNameToUse -ErrorAction Stop
                        } else {
                            Set-Printer -Name $printerName -ComputerName $ComputerName -Shared $true -ShareName $shareNameToUse -ErrorAction Stop
                        }
                        Write-Log "  Drucker geteilt: $printerName (Share: $shareNameToUse)" "INFO"
                        $sharedPrintersCount++
                    } catch {
                        Write-Log "  WARNUNG: Konnte Drucker nicht teilen '$printerName' mit ShareName '$shareNameToUse': $($_.Exception.Message)" "WARNING"
                        # Versuche es ohne ShareName
                        try {
                            if ($useLocalhost) {
                                Set-Printer -Name $printerName -Shared $true -ErrorAction Stop
                            } else {
                                Set-Printer -Name $printerName -ComputerName $ComputerName -Shared $true -ErrorAction Stop
                            }
                            Write-Log "  Drucker geteilt (ohne ShareName): $printerName" "INFO"
                            $sharedPrintersCount++
                        } catch {
                            Write-Log "  FEHLER: Konnte Drucker nicht teilen '$printerName': $($_.Exception.Message)" "ERROR"
                        }
                    }
                } else {
                    # Explizit nicht teilen (nur für Microsoft-Drucker)
                    try {
                        if ($useLocalhost) {
                            Set-Printer -Name $printerName -Shared $false -ErrorAction Stop
                        } else {
                            Set-Printer -Name $printerName -ComputerName $ComputerName -Shared $false -ErrorAction Stop
                        }
                        Write-Log "  Drucker nicht geteilt: $printerName" "INFO"
                        $notSharedPrintersCount++
                    } catch {
                        Write-Log "  WARNUNG: Konnte Shared-Status nicht setzen für '$printerName': $($_.Exception.Message)" "WARNING"
                    }
                }
                
                # Setze weitere Eigenschaften falls vorhanden
                if ($printer.Description) {
                    try {
                        if ($useLocalhost) {
                            Set-Printer -Name $printerName -Comment $printer.Description -ErrorAction Stop
                        } else {
                            Set-Printer -Name $printerName -ComputerName $ComputerName -Comment $printer.Description -ErrorAction Stop
                        }
                    } catch {
                        Write-Log "  WARNUNG: Konnte Comment nicht setzen für '$printerName': $($_.Exception.Message)" "WARNING"
                    }
                }
                
                Write-Log "  Drucker erstellt: $printerName" "INFO"
                $printerSuccess++
                
                # Füge zu importierten Druckern hinzu
                $importedPrinters += @{
                    Name = $printerName
                    ComputerName = $ComputerName
                    ImportDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    SourceFile = $fileName
                }
                
            } catch {
                Write-Log "  FEHLER beim Erstellen von Drucker '$($printer.Name)': $($_.Exception.Message)" "ERROR"
            }
        }
        
        Write-Log "Drucker importiert: $printerSuccess erfolgreich, $printerSkipped übersprungen" "SUCCESS"
        Write-Host "  [OK] Drucker importiert: $printerSuccess erfolgreich, $printerSkipped übersprungen" -ForegroundColor Green
        $printerImportCount++
        
    } catch {
        Write-Log "FEHLER beim Import der Drucker: $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
        $printerErrorCount++
    }
    
    Write-Host ""
    
    # Frage ob fortgefahren werden soll (außer wenn SkipConfirmation gesetzt ist)
    if (-not $SkipConfirmation) {
        $continue = Read-Host "Möchten Sie mit der nächsten Datei fortfahren? (J/N)"
        if ($continue -notmatch "^[JjYy]") {
            Write-Log "Import abgebrochen vom Benutzer" "WARNING"
            Write-Host "Import abgebrochen." -ForegroundColor Yellow
            break
        }
        Write-Host ""
    }
}

# Speichere Liste der importierten Drucker (für Fallback)
if ($importedPrinters.Count -gt 0) {
    try {
        $importedPrinters | ConvertTo-Json -Depth 10 | Out-File -FilePath $ImportedPrintersFile -Encoding UTF8
        Write-Log "Liste der importierten Drucker gespeichert: $ImportedPrintersFile" "INFO"
    } catch {
        Write-Log "WARNUNG: Konnte Liste der importierten Drucker nicht speichern: $($_.Exception.Message)" "WARNING"
    }
}

# ==================================================================
# ZUSAMMENFASSUNG
# ==================================================================
Write-Host ""
Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Ports:" -ForegroundColor Yellow
Write-Host "  - Erfolgreich: $portImportCount" -ForegroundColor $(if ($portErrorCount -eq 0) { "Green" } else { "White" })
Write-Host "  - Fehler: $portErrorCount" -ForegroundColor $(if ($portErrorCount -gt 0) { "Red" } else { "White" })

Write-Host ""
Write-Host "Drucker:" -ForegroundColor Yellow
Write-Host "  - Erfolgreich: $printerImportCount" -ForegroundColor $(if ($printerErrorCount -eq 0) { "Green" } else { "White" })
Write-Host "  - Fehler: $printerErrorCount" -ForegroundColor $(if ($printerErrorCount -gt 0) { "Red" } else { "White" })
Write-Host "  - Neue Drucker erkannt: $($importedPrinters.Count)" -ForegroundColor $(if ($importedPrinters.Count -gt 0) { "Green" } else { "Gray" })
Write-Host "  - Geteilte Drucker: $sharedPrintersCount" -ForegroundColor $(if ($sharedPrintersCount -gt 0) { "Green" } else { "Yellow" })
Write-Host "  - Nicht geteilte Drucker: $notSharedPrintersCount" -ForegroundColor $(if ($notSharedPrintersCount -eq 0) { "Green" } else { "Gray" })

Write-Host ""
Write-Log "Import abgeschlossen" "INFO"
Write-Log "Log-Datei: $ImportLogFile" "INFO"
if ($importedPrinters.Count -gt 0) {
    Write-Log "Importierte Drucker-Liste: $ImportedPrintersFile" "INFO"
    Write-Host ""
    Write-Host "WICHTIG: Die Liste der importierten Drucker wurde gespeichert für das Fallback-Script." -ForegroundColor Yellow
    Write-Host "Datei: $ImportedPrintersFile" -ForegroundColor Gray
}

Write-Host ""

