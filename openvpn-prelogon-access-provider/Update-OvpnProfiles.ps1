# PowerShell-Skript zur Anpassung von .ovpn-Dateien mit Auswahlabfrage

# Funktion zur Anpassung der .ovpn-Datei mit dynamischem Port und zusaetzlichen Optionen
function Update-OvpnFile {
    param (
        [string]$InputFilePath,
        [string]$OutputFilePath,
        [int]$Port
    )

    $content = Get-Content -Path $InputFilePath
    $content = $content | Where-Object { $_ -notmatch '^(management|auth-retry interact|management-query-passwords|management-hold|auth-nocache|management-forget-disconnect)' }

    $plapOptions = @"
management 127.0.0.1 $Port
management-query-passwords
auth-user-pass
management-hold
auth-retry interact
auth-nocache
management-forget-disconnect
mssfix 1200
disable-dco
"@

    $content += $plapOptions
    Set-Content -Path $OutputFilePath -Value $content
}

# Funktion zur Ermittlung des naechsten freien Ports mit Validierung
function Get-FreePort {
    param (
        [int]$StartPort = 7505,
        [int]$EndPort = 7600,
        [string[]]$UsedPorts
    )

    for ($port = $StartPort; $port -le $EndPort; $port++) {
        if ($port -notin $UsedPorts) {
            $isFree = !(netstat -ano | findstr ":$port")
            if ($isFree) {
                return $port
            }
        }
    }

    throw "Kein freier Port im Bereich $StartPort-$EndPort gefunden."
}

# Funktion zum Hinzufuegen des Registry-Eintrags ohne Konsolenausgabe
function Add-RegistryEntry {
    $plapRegFile = "C:\Program Files\OpenVPN\bin\openvpn-plap-install.reg"
    if (Test-Path $plapRegFile) {
        Start-Process -FilePath "reg" -ArgumentList "import `"$plapRegFile`"" -NoNewWindow -Wait
    } else {
        exit
    }
}

# Funktion zum Neustarten der OpenVPN-Dienste
function Restart-OpenVPNServices {
    $services = @("OpenVPNService", "OpenVPN Interactive Service")
    foreach ($service in $services) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Stop-Service -Name $service -Force
            Start-Service -Name $service
            Write-Host "Dienst neu gestartet: $service"
        } else {
            Write-Host "Dienst nicht gefunden: $service"
        }
    }
}

# Hauptskript

# Fuege Registry-Eintrag hinzu
Add-RegistryEntry

Write-Host "Suche nach .ovpn-Dateien in C:\EDV..."
$ovpnFiles = Get-ChildItem -Path "C:\EDV" -Filter "*.ovpn"

if ($ovpnFiles.Count -eq 0) {
    Write-Host "Keine .ovpn-Dateien gefunden."
    exit
}

# Liste die gefundenen Dateien auf und lasse den Benutzer eine auswählen
Write-Host "Gefundene .ovpn-Dateien:"
for ($i = 0; $i -lt $ovpnFiles.Count; $i++) {
    Write-Host "[$i] $($ovpnFiles[$i].Name)"
}

# Benutzerabfrage fuer die Auswahl
$selection = Read-Host "Bitte die Nummer der zu bearbeitenden .ovpn-Datei eingeben"
if ($selection -notmatch "^\d+$" -or [int]$selection -ge $ovpnFiles.Count) {
    Write-Host "Ungültige Auswahl."
    exit
}

# Ausgewaehlte Datei
$selectedFile = $ovpnFiles[$selection].FullName
Write-Host "Ausgewaehlte Datei: $selectedFile"

# Vorhandene Ports im config-auto-Verzeichnis auslesen
$configAutoPath = "C:\Program Files\OpenVPN\config-auto"
$usedPorts = @()

if (Test-Path $configAutoPath) {
    $autoFiles = Get-ChildItem -Path $configAutoPath -Filter "*.ovpn"
    foreach ($file in $autoFiles) {
        $content = Get-Content -Path $file.FullName
        foreach ($line in $content) {
            if ($line -match "management 127.0.0.1 (\d+)") {
                $usedPorts += [int]$matches[1]
            }
        }
    }
}

# Freien Port finden
$freePort = Get-FreePort -UsedPorts $usedPorts
$usedPorts += $freePort
Write-Host "Verwende freien Port: $freePort"

# Benutzer zur Eingabe des neuen Dateinamens auffordern
$newFileName = Read-Host "Geben Sie den neuen Namen fuer die Datei ohne Erweiterung ein (z. B. vpn-config)"
$newFileName += ".ovpn"

# Zielpfad fuer die angepasste Datei
if (-not (Test-Path $configAutoPath)) {
    Write-Host "Erstelle Zielverzeichnis: $configAutoPath"
    New-Item -Path $configAutoPath -ItemType Directory
}

$outputFile = Join-Path -Path $configAutoPath -ChildPath $newFileName
Update-OvpnFile -InputFilePath $selectedFile -OutputFilePath $outputFile -Port $freePort
Write-Host "Datei erfolgreich bearbeitet und gespeichert: $outputFile"

# OpenVPN-Dienste neu starten
Restart-OpenVPNServices

Write-Host "Die Datei wurde erfolgreich bearbeitet und die Dienste neu gestartet!" -ForegroundColor Green
