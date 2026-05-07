# Assembly f�r Windows Forms laden (wird f�r TaskbarProgress ben�tigt)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# Fehlerausgaben unterdr�cken
$ErrorActionPreference = 'SilentlyContinue'

# Pfad zum Installer
$installerPath = "C:\EDV\Windows11InstallationAssistant"

# Parameter f�r die stille Installation
$arguments = "/Install /QuietInstall /SkipEULA /SkipCompatCheck /NoRestartUI /MinimizeToTaskBar /ShowProgressInTaskBarIcon /ReUseCatalog /SkipSelfUpdate /AlwaysOverwrite /EnableTelemetry /ClientID Win10UA /SetPriorityLow"

try {
    # Taskbar-Progress Registry-Einstellungen pr�fen/setzen
    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $registryPath -Name "TaskbarProgressEnabled" -Value 1 -Type DWord
    
    # Prozess mit "cmd /c start" starten, was oft besser mit der Taskbar funktioniert
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c start /MIN """" ""$installerPath"" $arguments"
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized
    $psi.UseShellExecute = $false
    
    $process = [System.Diagnostics.Process]::Start($psi)
    
    # Kurz warten, damit der Prozess starten kann
    Start-Sleep -Seconds 2
    
    # Hauptprozess des Installers finden
    $installerProcess = Get-Process | Where-Object {$_.MainWindowTitle -like "*Windows 11*"} | Select-Object -First 1
    
    if ($installerProcess) {
        # Fenster-Handle des Installers finden
        $windowHandle = $installerProcess.MainWindowHandle
        
        # Taskbar-Button f�r das Fenster erstellen/aktualisieren
        $TaskbarProgress = [Microsoft.VisualBasic.Interaction]::AppActivate($windowHandle)
    }
}
catch {
    # Fehler still abfangen
}
finally {
    # Skript beenden
    exit 0
}
