# TeamsFix_SYSTEM_NewTeams_2025_Final.ps1 - baramundi als SYSTEM

$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsFix.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
function Log { param($msg); Add-Content -Path $logFile -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): [SYSTEM] $msg" }

Log "=== SYSTEM-Teil startet (inkl. AlwaysInstallElevated-Fix + Add-in Deinstallation) ==="

# 1. AlwaysInstallElevated Policy deaktivieren (HKLM + HKU f�r alle User)
"SOFTWARE\Policies\Microsoft\Windows\Installer",
"SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" | ForEach-Object {
    $path = "HKLM:\$_"
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name AlwaysInstallElevated -Force -ErrorAction SilentlyContinue
        Log "AlwaysInstallElevated aus $path entfernt"
    }
}

# F�r alle bereits geladenen User-Hives (auch wenn niemand angemeldet ist)
Get-ChildItem "HKU:" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'S-1-5-21' } | ForEach-Object {
    $userPath = "$($_.PSPath)\SOFTWARE\Policies\Microsoft\Windows\Installer"
    if (Test-Path $userPath) {
        Remove-ItemProperty -Path $userPath -Name AlwaysInstallElevated -Force -ErrorAction SilentlyContinue
        Log "AlwaysInstallElevated aus HKU entfernt ($($_.PSChildName))"
    }
}

# Prozesse beenden
Stop-Process -Name OUTLOOK,Teams,ms-teams -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

function Convert-GuidToInstallerFormat {
    param([string]$guid)
    $g = ($guid -replace '[{}\-]','')
    if ($g.Length -ne 32) { return $null }
    $r = -join ($g.Substring(0,8).ToCharArray()[7..0])
    $r += -join ($g.Substring(8,4).ToCharArray()[3..0])
    $r += -join ($g.Substring(12,4).ToCharArray()[3..0])
    for ($i = 16; $i -lt 28; $i += 2) { $r += $g[$i+1] + $g[$i] }
    return $r.ToUpper()
}

# Funktion: Windows Installer Datenbank bereinigen
function Remove-InstallerDatabaseEntries {
    param([string]$guid)
    Log "Bereinige Windows Installer Datenbank fuer GUID: $guid"
    
    $crypticGuid = Convert-GuidToInstallerFormat -guid $guid
    if ($crypticGuid) {
        $paths = @(
            "HKCR:\Installer\Products\$crypticGuid",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                try {
                    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                    Log "Installer-Datenbank Eintrag geloescht: $path"
                } catch {
                    Log "Konnte Installer-Datenbank Eintrag nicht loeschen: $path"
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
                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                Log "Uninstall Registry geloescht: $path"
            } catch {
                Log "Konnte Uninstall Registry nicht loeschen: $path"
            }
        }
    }
    
    # InstallSource in InstallProperties loeschen (System-Kontext)
    $installPropsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid\InstallProperties"
    if (Test-Path $installPropsPath) {
        try {
            Remove-ItemProperty -Path $installPropsPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
            Log "InstallSource entfernt (System-Kontext)"
        } catch {
            Log "Konnte InstallSource nicht entfernen (System-Kontext)"
        }
    }
    
    # InstallSource in InstallProperties loeschen (User-Kontext - alle geladenen User)
    Get-ChildItem "HKU:" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'S-1-5-21' } | ForEach-Object {
        $userSid = $_.PSChildName
        $userInstallPropsPath = "$($_.PSPath)\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$userSid\Products\$crypticGuid\InstallProperties"
        if (Test-Path $userInstallPropsPath) {
            try {
                Remove-ItemProperty -Path $userInstallPropsPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                Log "InstallSource entfernt (User-Kontext: $userSid)"
            } catch {
                Log "Konnte InstallSource nicht entfernen (User-Kontext: $userSid)"
            }
        }
        
        # Auch Uninstall Registry in User-Kontext bereinigen
        $userUninstallPath = "$($_.PSPath)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
        if (Test-Path $userUninstallPath) {
            try {
                Remove-ItemProperty -Path $userUninstallPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                Log "InstallSource aus User Uninstall Registry entfernt ($userSid)"
            } catch {
                # Ignoriere Fehler
            }
        }
        
        # WICHTIG: Alte Registry-Stelle auch loeschen (HKU:\...\Software\Microsoft\Installer\Products\[ProductCode])
        # Diese alte Stelle wird von Windows Installer auch verwendet!
        $oldInstallerPath = "$($_.PSPath)\Software\Microsoft\Installer\Products\$guid"
        if (Test-Path $oldInstallerPath) {
            try {
                # SourceList aus alter Stelle entfernen
                $oldSourceListPath = "$oldInstallerPath\SourceList"
                if (Test-Path $oldSourceListPath) {
                    try {
                        # Explizit LastUsedSource, LastUsedType, LastUsedIndex entfernen
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedSource" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedType" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $oldSourceListPath -Name "LastUsedIndex" -Force -ErrorAction SilentlyContinue
                        Log "LastUsedSource aus alter Registry-Stelle entfernt (User: $userSid)"
                    } catch {
                        # Ignoriere Fehler
                    }
                    try {
                        Remove-Item $oldSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                        Log "SourceList-Ordner aus alter Registry-Stelle entfernt (User: $userSid)"
                    } catch {
                        # Ignoriere Fehler
                    }
                }
                # Kompletten Products-Eintrag aus alter Stelle entfernen (falls moeglich)
                try {
                    Remove-Item $oldInstallerPath -Recurse -Force -ErrorAction SilentlyContinue
                    Log "Kompletter Products-Eintrag aus alter Registry-Stelle entfernt (User: $userSid)"
                } catch {
                    # Ignoriere Fehler (kann geschuetzt sein)
                }
            } catch {
                Log "Konnte alte Registry-Stelle nicht vollstaendig loeschen (User: $userSid)"
            }
        }
    }
}

function Uninstall-MsiWithTimeout {
    param([string]$guid, [int]$timeoutSec = 120)
    $job = Start-Job -ScriptBlock { param($g) $p = Start-Process msiexec -ArgumentList "/x $g /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru; return $p.ExitCode } -ArgumentList $guid
    $done = Wait-Job $job -Timeout $timeoutSec
    if ($done) {
        $ec = Receive-Job $job; Remove-Job $job
        if ($ec -eq 0 -or $ec -eq 3010) { Log "Add-in deinstalliert (ExitCode: $ec)" } else { Remove-InstallerDatabaseEntries -guid $guid }
    } else {
        Stop-Job $job; Remove-Job $job -Force; Get-Process msiexec -EA SilentlyContinue | Stop-Process -Force; Remove-InstallerDatabaseEntries -guid $guid
        Log "MSI-Deinstallation Timeout, Registry bereinigt"
    }
    Start-Sleep -Seconds 2
}

$ADDIN_GUIDS = @("{0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}","{731F6BAA-A986-45C4-BCF4-724D65C1B15C}","{A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91}")
$uninstallBases = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
$foundGuids = @()

Log "Suche nach Teams Meeting Add-in in Registry"
foreach ($base in $uninstallBases) {
    if (-not (Test-Path $base)) { continue }
    Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        if (-not $p -or $p.DisplayName -notmatch "Teams Meeting Add-in|TeamsAddin|Teams.*Add.*in|Microsoft Teams Meeting") { return }
        $guid = $_.PSChildName
        Log "Gefunden: $($p.DisplayName) (GUID: $guid)"
        $foundGuids += $guid
        Uninstall-MsiWithTimeout -guid $guid
    }
}

Get-WmiObject Win32_Product | Where-Object { $_.Name -match "Teams Meeting Add-in|TeamsAddin|Teams.*Add.*in" } | ForEach-Object {
    Log "Deinstalliere per WMI: $($_.Name)"
    try {
        $r = $_.Uninstall()
        if ($r.ReturnValue -ne 0) { Uninstall-MsiWithTimeout -guid $_.IdentifyingNumber }
    } catch { Uninstall-MsiWithTimeout -guid $_.IdentifyingNumber }
}

foreach ($guid in $ADDIN_GUIDS) {
    if ($foundGuids -contains $guid) { continue }
    $k64 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    $k32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    if ((Test-Path $k64) -or (Test-Path $k32)) { Uninstall-MsiWithTimeout -guid $guid }
}

# Windows Installer Service neu starten nach Registry-Bereinigung
Log "Starte Windows Installer Service neu"
Restart-Service -Name msiserver -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Teams AppX Packages entfernen
Get-AppxPackage *Teams* -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*Teams*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Weitere Teams-Produkte entfernen
Get-WmiObject Win32_Product | Where-Object {$_.Name -like "*Teams*" -and $_.Name -notlike "*Meeting Add-in*"} | ForEach-Object {
    try {
        Log "Deinstalliere: $($_.Name)"
        $_.Uninstall() | Out-Null
    } catch {
        Log "Fehler bei Deinstallation von $($_.Name): $($_.Exception.Message)"
    }
}

# Office reparieren
$c2r = "$env:CommonProgramFiles\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
if (Test-Path $c2r) {
    Log "Starte Office-Reparatur"
    Start-Process $c2r -ArgumentList "/repair DisplayLevel=False ForceCloseApps=True" -Wait
    Log "Office repariert"
}

# New Teams installieren
$bootstrapper = "C:\EDV\Teams\teamsbootstrapper.exe"
$msix = "C:\EDV\Teams\MSTeams-x64.msix"
if ((Test-Path $bootstrapper) -and (Test-Path $msix)) {
    Log "Starte New Teams Installation"
    Start-Process $bootstrapper -ArgumentList "-p -o `"$msix`"" -Wait
    Log "New Teams installiert"
} else {
    Log "WARNUNG: Teams Bootstrapper oder MSIX nicht gefunden"
}

Log "=== SYSTEM-Teil fertig ==="
