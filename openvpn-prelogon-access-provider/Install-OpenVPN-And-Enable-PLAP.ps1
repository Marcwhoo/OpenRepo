# PowerShell-Skript zur OpenVPN-Installation und Konfiguration (Hintergrundmodus)

# Setze den Pfad zum Ordner, in dem sich das Skript und die Installationsdatei befinden
$basePath = "C:\EDV"

# Pfad zur Installationsdatei basierend auf dem Ordner
$installerPath = Get-ChildItem -Path $basePath -Filter "OpenVPN-*-amd64.msi" | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }


# Pruefe, ob die Installationsdatei existiert
if (-Not (Test-Path $installerPath)) {
    Write-Host "Installationsdatei nicht gefunden, Skript wird beendet."
    if ($global:Transcribing -eq $true) { Stop-Transcript }
    exit
}

# Installiere OpenVPN mit GUI und Pre-Logon
Write-Host "Starte OpenVPN-Installation..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/qn /norestart /i `"$installerPath`"" -Wait


# Sicherstellen, dass die Installation abgeschlossen ist
$installationPath = "C:\Program Files\OpenVPN"
if (-Not (Test-Path $installationPath)) {
    Write-Host "Installation scheint nicht abgeschlossen zu sein. Skript wird beendet."
    if ($global:Transcribing -eq $true) { Stop-Transcript }
    exit
}

# Autostart-Eintrag entfernen
Write-Host "Entferne Autostart-Eintrag..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OpenVPN-GUI" -ErrorAction SilentlyContinue

# Verknuepfungen entfernen
Write-Host "Entferne Verknuepfungen..."
Remove-Item -Path "C:\Users\Public\Desktop\OpenVPN GUI.lnk" -ErrorAction SilentlyContinue -Force
Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\OpenVPN" -Recurse -Force -ErrorAction SilentlyContinue
$taskbarPath = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
Remove-Item -Path "$taskbarPath\OpenVPN GUI.lnk" -ErrorAction SilentlyContinue -Force

# GUI-Konfigurationsdatei setzen
Write-Host "Setze OpenVPN-GUI-Einstellungen..."
$guiConfigPath = "$env:APPDATA\OpenVPN-GUI\config.ini"
if (-Not (Test-Path $guiConfigPath)) {
    Write-Host "Erstelle GUI-Konfigurationsdatei: $guiConfigPath"
    New-Item -Path $guiConfigPath -ItemType File -Force
}
$configContent = @"
[Settings]
EnablePreLogonAccessProvider=true
EnableAutostart=false
"@
Set-Content -Path $guiConfigPath -Value $configContent

# Pruefe die Dienste und starte sie neu
Write-Host "Starte OpenVPN-Dienste neu..."
$services = @("OpenVPNService", "OpenVPN Interactive Service")
foreach ($service in $services) {
    if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        Stop-Service -Name $service -Force
        Start-Service -Name $service
        Write-Host "Dienst erfolgreich neu gestartet: $service"
    } else {
        Write-Host "Dienst nicht gefunden: $service"
    }
}

# Installationsdatei loeschen
Write-Host "Loesche Installationsdatei..."
Remove-Item -Path $installerPath -ErrorAction SilentlyContinue -Force

# PLAP aktivieren (Registry-Eintrag)
Write-Host "Aktiviere Pre-Logon Access Provider..."
$plapRegFile = "C:\Program Files\OpenVPN\bin\openvpn-plap-install.reg"
if (Test-Path $plapRegFile) {
    reg import "$plapRegFile"
    Write-Host "PLAP-Registrierungsdatei erfolgreich importiert."
} else {
    Write-Host "PLAP-Registrierungsdatei nicht gefunden: $plapRegFile"
}

# Transkript beenden, falls aktiv
if ($global:Transcribing -eq $true) {
    Stop-Transcript
}

# Skript selbst loeschen
Write-Host "Skript loescht sich selbst..."
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
