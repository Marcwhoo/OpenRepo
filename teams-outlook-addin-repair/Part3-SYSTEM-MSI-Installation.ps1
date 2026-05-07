# TeamsFix_SYSTEM_MSI_Installation.ps1 - MSI im SYSTEM-Kontext (baramundi: nach part2)

$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsFix.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
function Log { param($msg); Add-Content -Path $logFile -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): [SYSTEM] $msg" }

$ADDIN_GUIDS = @("{0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}","{731F6BAA-A986-45C4-BCF4-724D65C1B15C}","{A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91}")

Log "=== SYSTEM MSI-Installation startet ==="

$msiSource = $null
Get-ChildItem "C:\Users" -Directory -EA SilentlyContinue | Where-Object { $_.Name -notmatch "Public|Default" } | ForEach-Object {
    $t = "$($_.FullName)\AppData\Local\Temp\TeamsAddinInstaller.msi"
    if ((Test-Path $t) -and (Get-Item $t -EA SilentlyContinue).Length -gt 1000 -and -not $msiSource) { $msiSource = $t }
}
if (-not $msiSource -and (Test-Path "$env:TEMP\TeamsAddinInstaller.msi")) { $f = Get-Item "$env:TEMP\TeamsAddinInstaller.msi" -EA SilentlyContinue; if ($f.Length -gt 1000) { $msiSource = $f.FullName } }
if (-not $msiSource) {
    $appPath = (Get-AppxPackage MSTeams -EA SilentlyContinue).InstallLocation
    if ($appPath -and (Test-Path "$appPath\MicrosoftTeamsMeetingAddinInstaller.msi")) { $msiSource = "$appPath\MicrosoftTeamsMeetingAddinInstaller.msi" }
}
if (-not $msiSource) {
    Get-ChildItem "C:\Program Files\WindowsApps" -Filter "MSTeams_*" -Directory -EA SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
        $t = "$($_.FullName)\MicrosoftTeamsMeetingAddinInstaller.msi"
        if ((Test-Path $t) -and -not $msiSource) { $msiSource = $t }
    }
}

if (-not $msiSource -or -not (Test-Path $msiSource)) { Log "FEHLER: MSI nicht gefunden"; exit 1 }
Log "MSI gefunden: $msiSource"

$isClickToRun = (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot\Virtual\VirtualOutlook")
Log "Office: $(if ($isClickToRun) { 'Click-to-Run' } else { 'MSI' })"

Log "Bereinige Windows Installer Datenbank vollstaendig (System-Kontext)..."

function Convert-GuidToInstallerFormat {
    param([string]$guid)
    $g = ($guid -replace '[{}\-]','')
    if ($g.Length -ne 32) { return $null }
    $r = -join ($g.Substring(0,8).ToCharArray()[7..0]); $r += -join ($g.Substring(8,4).ToCharArray()[3..0]); $r += -join ($g.Substring(12,4).ToCharArray()[3..0])
    for ($i = 16; $i -lt 28; $i += 2) { $r += $g[$i+1] + $g[$i] }
    return $r.ToUpper()
}

foreach ($guid in $ADDIN_GUIDS) {
    $crypticGuid = Convert-GuidToInstallerFormat -guid $guid
    if ($crypticGuid) {
        # System-Kontext Product komplett loeschen
        $systemProductPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid"
        if (Test-Path $systemProductPath) {
            try {
                Remove-Item $systemProductPath -Recurse -Force -ErrorAction SilentlyContinue
                Log "System Product-Eintrag geloescht: $systemProductPath"
            } catch {
                Log "Konnte System Product-Eintrag nicht loeschen: $($_.Exception.Message)"
            }
        }
        
        # SourceList aus System-Kontext entfernen
        $systemSourceListPath = "$systemProductPath\SourceList"
        if (Test-Path $systemSourceListPath) {
            try {
                Remove-Item $systemSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                Log "System SourceList geloescht: $systemSourceListPath"
            } catch {
                Log "Konnte System SourceList nicht loeschen: $($_.Exception.Message)"
            }
        }
        
        # Fuer alle User: SourceList bereinigen
        Get-ChildItem "HKU:" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'S-1-5-21' } | ForEach-Object {
            $userSid = $_.PSChildName
            $userProductPath = "$($_.PSPath)\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$userSid\Products\$crypticGuid"
            if (Test-Path $userProductPath) {
                $userSourceListPath = "$userProductPath\SourceList"
                if (Test-Path $userSourceListPath) {
                    try {
                        Remove-Item $userSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                        Log "User SourceList geloescht fuer SID: $userSid"
                    } catch {
                        # Ignoriere Fehler
                    }
                }
                # InstallSource aus InstallProperties entfernen
                $userInstallPropsPath = "$userProductPath\InstallProperties"
                if (Test-Path $userInstallPropsPath) {
                    try {
                        Remove-ItemProperty -Path $userInstallPropsPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $userInstallPropsPath -Name "SourceList" -Force -ErrorAction SilentlyContinue
                        Log "InstallSource aus User-InstallProperties entfernt fuer SID: $userSid"
                    } catch {
                        # Ignoriere Fehler
                    }
                }
            }
            
            # Alte Registry-Stelle auch bereinigen
            $oldInstallerPath = "$($_.PSPath)\Software\Microsoft\Installer\Products\$guid"
            if (Test-Path $oldInstallerPath) {
                $oldSourceListPath = "$oldInstallerPath\SourceList"
                if (Test-Path $oldSourceListPath) {
                    try {
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedSource" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedType" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedIndex" -Force -ErrorAction SilentlyContinue
                        Remove-Item $oldSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                        Log "Alte SourceList-Stelle geloescht fuer SID: $userSid"
                    } catch {
                        # Ignoriere Fehler
                    }
                }
            }
        }
    }
    
    # Uninstall Registry loeschen
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    )
    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            try {
                Remove-ItemProperty -Path $path -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                Log "InstallSource aus Uninstall Registry entfernt: $path"
            } catch {
                # Ignoriere Fehler
            }
        }
    }
}

Start-Sleep -Seconds 2

# Kopiere MSI in Standard-Pfad fuer Windows Installer (umgeht SourceList-Probleme)
$standardMsiPath = "C:\Windows\Temp\TeamsAddinInstaller.msi"
try {
    Copy-Item $msiSource $standardMsiPath -Force
    Log "MSI nach Standard-Pfad kopiert: $standardMsiPath"
    $msiSource = $standardMsiPath
} catch {
    Log "WARNUNG: Konnte MSI nicht nach Standard-Pfad kopieren, verwende Original: $($_.Exception.Message)"
}

$logFileMsi = "$env:TEMP\TeamsAddinInstall-System.log"
$msiArgs = "/i `"$msiSource`" /qn /norestart /l*v `"$logFileMsi`" SOURCELIST=`"C:\Windows\Temp`""

if ($isClickToRun) {
    $loggedOnUser = (Get-WmiObject Win32_ComputerSystem).UserName
    if ($loggedOnUser) {
        $userName = $loggedOnUser.Split('\')[-1]
        $userProfile = "C:\Users\$userName"
        if (Test-Path $userProfile) {
            $targetDir = "$userProfile\AppData\Local\Microsoft\TeamsMeetingAdd-in\"
            $msiArgs += " TARGETDIR=`"$targetDir`""
            Log "Click-to-Run: Verwende TARGETDIR fuer User: $userName"
        }
    }
} else {
    $msiArgs += " ALLUSERS=1"
}

Log "Starte MSI-Installation..."
$process = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

$installOk = $false
if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) { Log "Add-in installiert (ExitCode: $($process.ExitCode))"; $installOk = $true }
else {
    Log "WARNUNG: Installation fehlgeschlagen (ExitCode: $($process.ExitCode))"
    if (Test-Path $logFileMsi) { Log "MSI-Log: $((Get-Content $logFileMsi -Tail 20) -join ' | ')" }
    
    Log "Versuche Reparatur-Installation (REINSTALL=ALL)..."
    $repairArgs = $msiArgs + " REINSTALL=ALL REINSTALLMODE=vomus"
    $p2 = Start-Process msiexec -ArgumentList $repairArgs -Wait -PassThru -NoNewWindow
    if ($p2.ExitCode -eq 0 -or $p2.ExitCode -eq 3010) { Log "Add-in per Reparatur installiert"; $installOk = $true }
    else {
        Log "Versuche Fallback mit expliziter Deinstallation..."
        foreach ($g in $ADDIN_GUIDS) {
            Start-Process msiexec -ArgumentList "/x $g /qn /norestart" -Wait -NoNewWindow -EA SilentlyContinue | Out-Null
        }
        Start-Sleep -Seconds 2
        $p3 = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        if ($p3.ExitCode -eq 0 -or $p3.ExitCode -eq 3010) { Log "Add-in nach Deinstallation installiert"; $installOk = $true } else { Log "FEHLER: Alle Versuche fehlgeschlagen (ExitCode: $($p3.ExitCode))" }
    }
}

if ($installOk) {
    Log "Add-in installiert - registriere COM-Klassen..."
    
    # WICHTIG: regsvr32 als SYSTEM ausfuehren fuer COM-Registrierung unter HKLM
    # Das ist noetig weil die MSI mit TARGETDIR die COM-Klassen nicht selbst registriert
    $loggedOnUser = (Get-WmiObject Win32_ComputerSystem).UserName
    if ($loggedOnUser) {
        $userName = $loggedOnUser.Split('\')[-1]
        $dll64 = "C:\Users\$userName\AppData\Local\Microsoft\TeamsMeetingAdd-in\x64\Microsoft.Teams.AddinLoader.dll"
        $dll86 = "C:\Users\$userName\AppData\Local\Microsoft\TeamsMeetingAdd-in\x86\Microsoft.Teams.AddinLoader.dll"
        
        if (Test-Path $dll64) {
            $p = Start-Process regsvr32 -ArgumentList "/s `"$dll64`"" -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -eq 0) { Log "x64 DLL COM-registriert (HKLM)" } 
            else { Log "WARNUNG: x64 DLL COM-Registrierung fehlgeschlagen (ExitCode: $($p.ExitCode))" }
        }
        if (Test-Path $dll86) {
            $p = Start-Process regsvr32 -ArgumentList "/s `"$dll86`"" -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -eq 0) { Log "x86 DLL COM-registriert (HKLM)" } 
            else { Log "WARNUNG: x86 DLL COM-Registrierung fehlgeschlagen (ExitCode: $($p.ExitCode))" }
        }
    }
    
    Log "Add-in installiert und COM-registriert - part4 (USER) setzt Registry und startet Outlook/Teams"
}

Log "=== SYSTEM MSI-Installation abgeschlossen ==="

