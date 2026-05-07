# Pfad zum Verzeichnis, das gel�scht werden soll
$folderPath = "C:\EDV\Office 2016 Professional Plus 64bit German"

# Name des geplanten Tasks
$taskName = "DeleteFolderOnBoot"

# PowerShell-Befehl, der beim Start ausgef�hrt wird
$deleteCommand = @"
# Versuche, den Ordner zu l�schen (inklusive Unterordner und Dateien)
Remove-Item -Path '$folderPath' -Recurse -Force -ErrorAction SilentlyContinue
# L�sche den Task selbst nach Ausf�hrung
Unregister-ScheduledTask -TaskName '$taskName' -Confirm:\$false -ErrorAction SilentlyContinue
"@

# Schreibe den Befehl in eine tempor�re PS1-Datei
$scriptPath = "$env:TEMP\DeleteFolderOnBoot.ps1"
Set-Content -Path $scriptPath -Value $deleteCommand

# Erstelle den Task im Taskplaner
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Registriere den Task mit Administratorrechten
Register-ScheduledTask -TaskName $taskName `
                      -Action $action `
                      -Trigger $trigger `
                      -Settings $settings `
                      -Description "L�scht den Ordner $folderPath beim n�chsten Start" `
                      -RunLevel Highest `
                      -Force

Write-Host "Der Ordner '$folderPath' wird beim n�chsten Neustart gel�scht."
