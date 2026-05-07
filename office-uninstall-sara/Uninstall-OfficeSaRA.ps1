# Protokolldatei
$logDir = "C:\EDV\ODT"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force }
$logFile = "$logDir\sara_uninstall_log.txt"
Add-Content -Path $logFile -Value "Skript gestartet: $(Get-Date)"
function Write-Log { param ($Message); Add-Content -Path $logFile -Value $Message }

# Office- und XPhone-Prozesse und Dienste gr�ndlich beenden (Teams-Prozess bleibt enthalten)
Write-Log "Beende Office- und XPhone-Prozesse und Dienste gr�ndlich..."
$officeProcesses = @("winword", "excel", "powerpnt", "outlook", "msaccess", "mspub", "onenote", "visio", "lync", "teams", "groove", "infopath", "msproject", "OfficeClickToRun", "appvshnotify", "msosync", "msoia", "setup*", "msiexec", "XPhoneConnect", "XPhoneClient", "XPhone*")
Get-Process -Name $officeProcesses -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Service -Name "ClickToRunSvc" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "ose" -Force -ErrorAction SilentlyContinue
Write-Log "Office- und XPhone-Prozesse und Dienste beendet."

# Pr�fen, ob Office installiert ist
$officeReg = "HKLM:\SOFTWARE\Microsoft\Office"
if (-not (Test-Path $officeReg)) {
    Write-Log "Keine Office-Installation gefunden, �berspringe SaRAcmd, fahre mit Bereinigung fort."
    goto Cleanup
}

# SaRAcmd ausf�hren mit 20-Minuten-Timeout nur f�r SaRAcmd
$saRAcmdPath = "C:\EDV\ODT\SaRACmd\SaRAcmd.exe"
if (Test-Path $saRAcmdPath) {
    Write-Log "Starte SaRAcmd-Deinstallation f�r Office..."
    $startTime = Get-Date
    $process = Start-Process -FilePath $saRAcmdPath -ArgumentList "-S OfficeScrubScenario -AcceptEula -OfficeVersion All" -NoNewWindow -PassThru
    $timeout = 1200  # 20 Minuten in Sekunden
    $elapsed = 0
    while (-not $process.HasExited -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 60
        $elapsed += 60
        $minutesElapsed = [math]::Round($elapsed / 60, 2)
        Write-Log "SaRAcmd l�uft noch, verstrichene Zeit: $minutesElapsed Minuten, Prozess-ID: $($process.Id)"
    }
    if ($process.HasExited) {
        $endTime = Get-Date
        $duration = [math]::Round(($endTime - $startTime).TotalMinutes, 2)
        Write-Log "SaRAcmd Exit-Code: $($process.ExitCode)"
        Write-Log "Dauer der Office-Deinstallation: $duration Minuten"
    } else {
        Write-Log "SaRAcmd hat das Zeitlimit von 20 Minuten �berschritten, beende nur SaRAcmd..."
        $process | Stop-Process -Force -ErrorAction SilentlyContinue
        $endTime = Get-Date
        $duration = [math]::Round(($endTime - $startTime).TotalMinutes, 2)
        Write-Log "SaRAcmd zwangsweise beendet nach $duration Minuten, fahre mit Skript fort."
    }
} else {
    Write-Log "SaRAcmd.exe nicht gefunden, fahre mit Bereinigung fort!"
}

# Office-Bereinigung (Teams wird nicht entfernt)
:Cleanup
Write-Log "Bereinigung von Office-Dateien und Registry..."
$directories = @("C:\Program Files (x86)\Microsoft Office", "C:\Program Files\Microsoft Office", "C:\ProgramData\Microsoft\Office")
$directories | Where-Object { Test-Path $_ } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\Windows\Temp" -Filter "Office*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$registryKeys = @("HKLM:\SOFTWARE\Microsoft\Office", "HKCU:\SOFTWARE\Microsoft\Office")
$registryKeys | Where-Object { Test-Path $_ } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "Office-Bereinigung abgeschlossen."

# SaRA-Logs pr�fen
$tempDir = [System.IO.Path]::GetTempPath()
$saraLog = Get-ChildItem -Path $tempDir -Filter "SaRA_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($saraLog) {
    Write-Log "Letzte SaRA-Log-Datei: $($saraLog.FullName)"
    $logContent = Get-Content $saraLog.FullName -Tail 10 -ErrorAction SilentlyContinue
    Write-Log "Letzte 10 Zeilen des Logs:`n$logContent"
}

# Skript erfolgreich beenden
Write-Log "Skript erfolgreich abgeschlossen: $(Get-Date)"
Exit 0
