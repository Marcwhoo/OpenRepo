# TeamsFix_USER_NewTeams_Addin_2025_Final.ps1 - baramundi als USER

$ErrorActionPreference = "Continue"
$ADDIN_GUIDS = @("{0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}","{731F6BAA-A986-45C4-BCF4-724D65C1B15C}","{A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91}")

$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsFix.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
function Log { param($msg); Add-Content -Path $logFile -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): [USER $env:USERNAME] $msg" }

# Error-Handler fuer unerwartete Fehler
trap {
    Log "KRITISCHER FEHLER: $($_.Exception.Message)"
    Log "Stack Trace: $($_.ScriptStackTrace)"
    continue
}

function Convert-GuidToInstallerFormat {
    param([string]$guid)
    $g = ($guid -replace '[{}\-]','')
    if ($g.Length -ne 32) { return $null }
    $r = -join ($g.Substring(0,8).ToCharArray()[7..0]); $r += -join ($g.Substring(8,4).ToCharArray()[3..0]); $r += -join ($g.Substring(12,4).ToCharArray()[3..0])
    for ($i = 16; $i -lt 28; $i += 2) { $r += $g[$i+1] + $g[$i] }
    return $r.ToUpper()
}

# Funktion: Windows Installer SourceList zuruecksetzen (fuer bereits installierte Produkte)
function Reset-InstallerSourceList {
    param([string]$guid)
    Log "Versuche Windows Installer SourceList zurueckzusetzen fuer GUID: $guid"
    
    try {
        # Pruefe ob Produkt installiert ist (per WMI)
        $product = Get-WmiObject Win32_Product -Filter "IdentifyingNumber='$guid'" -ErrorAction SilentlyContinue
        if (-not $product) {
            # Pruefe auch in Registry
            $uninstallPaths = @(
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
            )
            $isInstalled = $false
            foreach ($path in $uninstallPaths) {
                if (Test-Path $path) {
                    $isInstalled = $true
                    break
                }
            }
            if (-not $isInstalled) {
                Log "Produkt $guid nicht installiert - ForceSourceListResolution nicht noetig"
                return
            }
        }
        
        # Erstelle Windows Installer COM-Objekt
        $installer = New-Object -ComObject "WindowsInstaller.Installer" -ErrorAction Stop
        
        # Bestimme Username fuer per-user Installationen
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $userName = $currentIdentity.Name
        
        # Rufe ForceSourceListResolution auf (fuer per-user Installationen)
        Log "Rufe ForceSourceListResolution auf fuer Produkt $guid (User: $userName)"
        $installer.ForceSourceListResolution($guid, $userName)
        Log "ForceSourceListResolution erfolgreich aufgerufen - SourceList wird bei naechster Installation neu durchsucht"
        
        # COM-Objekt freigeben
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($installer) | Out-Null
    } catch {
        Log "WARNUNG: ForceSourceListResolution fehlgeschlagen fuer $guid : $($_.Exception.Message)"
        Log "Installation wird trotzdem versucht"
    }
}

# Funktion: Windows Installer Datenbank bereinigen (fuer USER-Context)
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
        
        # InstallSource und SourceList aus User-InstallProperties entfernen (User kann das selbst)
        try {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $userSid = $currentUser.User.Value
            $userInstallPropsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$userSid\Products\$crypticGuid\InstallProperties"
            if (Test-Path $userInstallPropsPath) {
                try {
                    Remove-ItemProperty -Path $userInstallPropsPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                    Log "InstallSource aus User-InstallProperties entfernt"
                } catch {
                    # Ignoriere Fehler
                }
                try {
                    Remove-ItemProperty -Path $userInstallPropsPath -Name "SourceList" -Force -ErrorAction SilentlyContinue
                    Log "SourceList aus User-InstallProperties entfernt"
                } catch {
                    # Ignoriere Fehler
                }
            }
            
            # Auch SourceList-Ordner entfernen falls vorhanden
            $userSourceListPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$userSid\Products\$crypticGuid\SourceList"
            if (Test-Path $userSourceListPath) {
                try {
                    Remove-Item $userSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                    Log "SourceList-Ordner aus User-Kontext entfernt"
                } catch {
                    # Ignoriere Fehler
                }
            }
        } catch {
            Log "Konnte User-SID nicht ermitteln fuer InstallSource-Bereinigung"
        }
        
        # WICHTIG: Alte Registry-Stelle auch loeschen (HKCU:\Software\Microsoft\Installer\Products\[ProductCode])
        # Diese alte Stelle wird von Windows Installer auch verwendet!
        $oldInstallerPath = "HKCU:\Software\Microsoft\Installer\Products\$guid"
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
                        Log "LastUsedSource aus alter Registry-Stelle entfernt"
                    } catch {
                        # Ignoriere Fehler
                    }
                    try {
                        Remove-Item $oldSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                        Log "SourceList-Ordner aus alter Registry-Stelle entfernt"
                    } catch {
                        # Ignoriere Fehler
                    }
                }
                # Kompletten Products-Eintrag aus alter Stelle entfernen (falls moeglich)
                try {
                    Remove-Item $oldInstallerPath -Recurse -Force -ErrorAction SilentlyContinue
                    Log "Kompletter Products-Eintrag aus alter Registry-Stelle entfernt"
                } catch {
                    # Ignoriere Fehler (kann geschuetzt sein)
                }
            } catch {
                Log "Konnte alte Registry-Stelle nicht vollstaendig loeschen: $oldInstallerPath"
            }
        }
        
        # InstallSource und SourceList auch aus System-InstallProperties entfernen (falls moeglich)
        $systemInstallPropsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid\InstallProperties"
        if (Test-Path $systemInstallPropsPath) {
            try {
                Remove-ItemProperty -Path $systemInstallPropsPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                Log "InstallSource aus System-InstallProperties entfernt"
            } catch {
                # Ignoriere Fehler (keine Admin-Rechte)
            }
            try {
                Remove-ItemProperty -Path $systemInstallPropsPath -Name "SourceList" -Force -ErrorAction SilentlyContinue
                Log "SourceList aus System-InstallProperties entfernt"
            } catch {
                # Ignoriere Fehler
            }
        }
        
        # SourceList-Ordner im System-Kontext entfernen (falls moeglich)
        $systemSourceListPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid\SourceList"
        if (Test-Path $systemSourceListPath) {
            try {
                Remove-Item $systemSourceListPath -Recurse -Force -ErrorAction SilentlyContinue
                Log "SourceList-Ordner aus System-Kontext entfernt"
            } catch {
                # Ignoriere Fehler (keine Admin-Rechte)
            }
        }
    }
    
    # Uninstall Registry loeschen
    $uninstallPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid",
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
}

Log "=== USER-Teil startet (inkl. 1625-Fix + Copy-Workaround + DisabledItem-Fix) ==="

# Pruefe Office Installationstyp (MSI oder Click-to-Run)
$isClickToRun = $false
$officePaths = @(
    "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Common\InstallRoot\Virtual\VirtualOutlook",
    "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot\Virtual\VirtualOutlook"
)
foreach ($path in $officePaths) {
    if (Test-Path $path) {
        $isClickToRun = $true
        Log "Office Click-to-Run Installation erkannt"
        break
    }
}
if (-not $isClickToRun) {
    Log "Office MSI Installation erkannt"
}

Stop-Process -Name OUTLOOK,Teams,ms-teams -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# HKCU AlwaysInstallElevated nochmal sicherheitshalber löschen
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name AlwaysInstallElevated -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" -Name AlwaysInstallElevated -Force -ErrorAction SilentlyContinue

# Teams Meeting Add-in aggressiv deinstallieren - zuerst per Registry
Log "Suche nach Teams Meeting Add-in in Registry (HKCU und HKLM)"
$uninstallKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
foreach ($uninstallBase in $uninstallKeys) {
    if (Test-Path $uninstallBase) {
        Get-ChildItem $uninstallBase -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props -and ($props.DisplayName -like "*Teams Meeting Add-in*" -or $props.DisplayName -like "*TeamsAddin*" -or $props.DisplayName -like "*Teams*Add*in*" -or $props.DisplayName -like "*Microsoft Teams Meeting*")) {
                $guid = $_.PSChildName
                $installDate = $props.InstallDate
                Log "Gefunden: $($props.DisplayName) (GUID: $guid, InstallDate: $installDate)"
                
                # Entferne alle gefundenen Teams Meeting Add-ins (unabhaengig von Datum)
                # Da wir alle Versionen neu installieren wollen
                Log "Entferne gefundenes Teams Meeting Add-in (alle Versionen)"
                Log "Deinstalliere per MSI mit Force: $guid"
                $proc = Start-Process msiexec -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress /f" -Wait -PassThru -ErrorAction SilentlyContinue
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                    Log "Add-in erfolgreich deinstalliert (ExitCode: $($proc.ExitCode))"
                } else {
                    Log "MSI-Deinstallation fehlgeschlagen (ExitCode: $($proc.ExitCode)), versuche Registry-Loeschung"
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 3
            }
        }
    }
}

# Zusaetzlich per WMI deinstallieren - alle Teams Add-in Varianten
$addinProducts = Get-WmiObject Win32_Product | Where-Object {
    $_.Name -like "*Teams Meeting Add-in*" -or 
    $_.Name -like "*TeamsAddin*" -or 
    $_.Name -like "*Teams*Add*in*" -or
    $_.Name -like "*Microsoft Teams Meeting*"
}
foreach ($product in $addinProducts) {
    try {
        Log "Deinstalliere Add-in per WMI: $($product.Name) (GUID: $($product.IdentifyingNumber))"
        $guid = $product.IdentifyingNumber
        $result = $product.Uninstall()
        if ($result.ReturnValue -eq 0) {
            Log "Add-in erfolgreich deinstalliert"
        } else {
            Log "Add-in Deinstallation fehlgeschlagen (ReturnCode: $($result.ReturnValue)), bereinige Registry"
            if ($guid) {
                Remove-InstallerDatabaseEntries -guid $guid
            }
        }
        Start-Sleep -Seconds 2
    } catch {
        Log "Fehler bei Add-in Deinstallation: $($_.Exception.Message)"
        if ($product.IdentifyingNumber) {
            Remove-InstallerDatabaseEntries -guid $product.IdentifyingNumber
        }
    }
}

foreach ($guid in $ADDIN_GUIDS) {
    $uninstallKeyHKCU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    $uninstallKeyHKLM64 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    $uninstallKeyHKLM32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
    if ((Test-Path $uninstallKeyHKCU) -or (Test-Path $uninstallKeyHKLM64) -or (Test-Path $uninstallKeyHKLM32)) {
        Log "Versuche MSI-Deinstallation per GUID mit Timeout: $guid"
        $job = Start-Job -ScriptBlock {
            param($g)
            $proc = Start-Process msiexec -ArgumentList "/x $g /qn /norestart REBOOT=ReallySuppress /f" -Wait -PassThru -ErrorAction SilentlyContinue
            return $proc.ExitCode
        } -ArgumentList $guid
        
        $timeout = 120
        $completed = Wait-Job $job -Timeout $timeout
        if ($completed) {
            $exitCode = Receive-Job $job
            Remove-Job $job
            Log "MSI-Deinstallation beendet (ExitCode: $exitCode)"
        } else {
            Log "MSI-Deinstallation haengt, entferne Registry direkt"
            Stop-Job $job
            Remove-Job $job -Force
            Get-Process msiexec -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if (Test-Path $uninstallKeyHKCU) { Remove-Item $uninstallKeyHKCU -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $uninstallKeyHKLM64) { Remove-Item $uninstallKeyHKLM64 -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $uninstallKeyHKLM32) { Remove-Item $uninstallKeyHKLM32 -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Start-Sleep -Seconds 2
    }
}

# Caches und Installationspfade loeschen
$pathsToClean = @(
    "$env:LOCALAPPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe",
    "$env:ProgramFiles\TeamsMeetingAddin",
    "${env:ProgramFiles(x86)}\TeamsMeetingAddin",
    "$env:ProgramData\Microsoft\TeamsMeetingAddin"
)
foreach ($path in $pathsToClean) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            Log "Pfad geloescht: $path"
        } catch {
            Log "Konnte Pfad nicht loeschen: $path - $($_.Exception.Message)"
        }
    }
}

# Registry vollständig bereinigen - sowohl MSI als auch Click-to-Run Pfade
$regPaths = @(
    "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKCU:\Software\Microsoft\Office\Teams",
    "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency",
    "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKLM:\SOFTWARE\Microsoft\Office\Teams",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Teams"
)
foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
            Log "Registry geloescht: $regPath"
        } catch {
            Log "Konnte Registry nicht loeschen: $regPath - $($_.Exception.Message)"
        }
    }
}

# DisabledItem-Einträge explizit entfernen
$resiliencyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency"
if (Test-Path $resiliencyPath) {
    Get-ChildItem $resiliencyPath -ErrorAction SilentlyContinue | ForEach-Object {
        $disabledItem = Get-ItemProperty $_.PSPath -Name "DisabledItem" -ErrorAction SilentlyContinue
        if ($disabledItem -and $disabledItem.DisabledItem -like "*TeamsAddin*") {
            Remove-ItemProperty -Path $_.PSPath -Name "DisabledItem" -Force -ErrorAction SilentlyContinue
            Log "DisabledItem entfernt: $($_.PSPath)"
        }
    }
}

Start-Sleep -Seconds 2

# New Teams starten (damit Add-in normalerweise installiert wird)
Log "Starte New Teams"
Start-Process "explorer.exe" -ArgumentList "shell:appsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
Start-Sleep -Seconds 60

Log "Suche nach Teams MSI-Datei..."
$msiSource = $null
$appPath = (Get-AppxPackage MSTeams -EA SilentlyContinue).InstallLocation
if ($appPath) { $msiSource = "$appPath\MicrosoftTeamsMeetingAddinInstaller.msi" }
if (-not $msiSource -or -not (Test-Path $msiSource)) {
    Get-ChildItem "C:\Program Files\WindowsApps" -Filter "MSTeams_*" -Directory -EA SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
        $t = "$($_.FullName)\MicrosoftTeamsMeetingAddinInstaller.msi"
        if ((Test-Path $t) -and -not $msiSource) { $msiSource = $t }
    }
}
if (-not $msiSource -or -not (Test-Path $msiSource)) { Start-Sleep -Seconds 30; $appPath = (Get-AppxPackage MSTeams -EA SilentlyContinue).InstallLocation; if ($appPath) { $msiSource = "$appPath\MicrosoftTeamsMeetingAddinInstaller.msi" } }
if ($msiSource) { Log "MSI gefunden: $msiSource" }

# Falls Add-in immer noch nicht da ist - Copy-Workaround (umgeht jede Policy)
if ($msiSource -and (Test-Path $msiSource)) {
    $msiCopy = "$env:TEMP\TeamsAddinInstaller.msi"
    Copy-Item $msiSource $msiCopy -Force
    Log "MSI nach TEMP kopiert: $msiCopy"
    
    # Pruefe ob MSI-Datei wirklich existiert und lesbar ist
    if (-not (Test-Path $msiCopy)) {
        Log "FEHLER: MSI-Datei konnte nicht nach TEMP kopiert werden"
    } else {
        $msiFile = Get-Item $msiCopy -ErrorAction SilentlyContinue
        if ($msiFile -and $msiFile.Length -lt 1000) {
            Log "WARNUNG: MSI-Datei scheint zu klein zu sein ($($msiFile.Length) Bytes) - moeglicherweise korrupt"
        } elseif ($msiFile) {
            Log "MSI-Datei OK: $($msiFile.Length) Bytes"
        }
        
        # InstallSource-Registry bereinigen um Error 1612 zu vermeiden
        Log "Bereinige InstallSource aus Uninstall Registry..."
        $allUninstallKeys = @(
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($uninstallBase in $allUninstallKeys) {
            if (Test-Path $uninstallBase) {
                Get-ChildItem $uninstallBase -ErrorAction SilentlyContinue | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($props -and ($props.DisplayName -like "*Teams Meeting Add-in*" -or $props.DisplayName -like "*TeamsAddin*")) {
                        try {
                            Remove-ItemProperty -Path $_.PSPath -Name "InstallSource" -Force -ErrorAction SilentlyContinue
                            Log "InstallSource entfernt fuer: $($props.DisplayName)"
                        } catch {
                            # Ignoriere Fehler (z.B. keine Rechte fuer HKLM)
                        }
                    }
                }
            }
        }
        
        Log "Bereinige Windows Installer Datenbank..."
        foreach ($g in $ADDIN_GUIDS) { Remove-InstallerDatabaseEntries -guid $g }
        Log "Setze SourceList zurueck (ForceSourceListResolution)..."
        foreach ($g in $ADDIN_GUIDS) { Reset-InstallerSourceList -guid $g }
        Start-Sleep -Seconds 3
        
        # MSI installieren - fuer Office 365 Click-to-Run und MSI
        # Bei Click-to-Run: TARGETDIR in LOCALAPPDATA (keine Admin-Rechte noetig)
        # WICHTIG: Reihenfolge: /i, MSI-Datei, /qn, /norestart, /l*v, Log-Datei, MSI-Eigenschaften
        if ($isClickToRun) {
            Log "Office 365 Click-to-Run erkannt - verwende TARGETDIR in LOCALAPPDATA"
            # Installation in User-Profil (keine Admin-Rechte noetig)
            $targetDir = "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in\"
            $msiArgs = "/i `"$msiCopy`" /qn /norestart /l*v `"$env:TEMP\TeamsAddinInstall.log`" TARGETDIR=`"$targetDir`" SOURCELIST=`"$env:TEMP`""
        } else {
            Log "Office MSI erkannt - Standard-Installation"
            $msiArgs = "/i `"$msiCopy`" /qn /norestart /l*v `"$env:TEMP\TeamsAddinInstall.log`" SOURCELIST=`"$env:TEMP`""
        }
        Log "Starte MSI-Installation (Source List sollte durch Bereinigung entfernt sein)"
        $process = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) { Log "Add-in erfolgreich installiert" }
        else {
            Log "WARNUNG: Installation fehlgeschlagen (ExitCode: $($process.ExitCode))"
            if (Test-Path "$env:TEMP\TeamsAddinInstall.log") { Log "MSI-Log: $((Get-Content "$env:TEMP\TeamsAddinInstall.log" -Tail 15) -join ' | ')" }
            $fallbackArgs = "/i `"$msiCopy`" /qn /norestart /l*v `"$env:TEMP\TeamsAddinInstall2.log`" SOURCELIST=`"$env:TEMP`""
            if ($isClickToRun) { $fallbackArgs += " TARGETDIR=`"$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in\`"" }
            $p2 = Start-Process msiexec -ArgumentList $fallbackArgs -Wait -PassThru -NoNewWindow
            if ($p2.ExitCode -eq 0) { Log "Add-in per Fallback installiert" } else { Log "FEHLER: Fallback fehlgeschlagen (ExitCode: $($p2.ExitCode))" }
        }
    }
} else {
    Log "FEHLER: Teams MSI-Datei konnte nicht gefunden werden"
    Log "HINWEIS: Teams moeglicherweise noch nicht vollstaendig installiert oder MSI fehlt"
    Log "Versuche manuelle Installation..."
    
    # Letzter Versuch: Suche in allen moeglichen Pfaden
    $possiblePaths = @(
        "C:\Program Files\WindowsApps\MSTeams_*\MicrosoftTeamsMeetingAddinInstaller.msi",
        "$env:LOCALAPPDATA\Microsoft\Teams\*\MicrosoftTeamsMeetingAddinInstaller.msi"
    )
    foreach ($pattern in $possiblePaths) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $msiSource = $found.FullName
            Log "MSI gefunden in alternativem Pfad: $msiSource"
            break
        }
    }
    
    if ($msiSource -and (Test-Path $msiSource)) {
        $msiCopy = "$env:TEMP\TeamsAddinInstaller.msi"
        Copy-Item $msiSource $msiCopy -Force
        foreach ($g in $ADDIN_GUIDS) { Remove-InstallerDatabaseEntries -guid $g; Reset-InstallerSourceList -guid $g }
        $msiArgs = "/i `"$msiCopy`" /qn /norestart /l*v `"$env:TEMP\TeamsAddinInstall.log`" SOURCELIST=`"$env:TEMP`""
        if ($isClickToRun) { $msiArgs += " TARGETDIR=`"$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in\`"" }
        $process = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) { Log "Add-in installiert (manuell gefunden)" } else { Log "FEHLER: Installation (ExitCode: $($process.ExitCode))" }
    } else {
        Log "KRITISCHER FEHLER: MSI-Datei konnte ueberhaupt nicht gefunden werden"
    }
}

Start-Sleep -Seconds 3

# Pruefe ob Add-in jetzt installiert wurde - beide moeglichen Pfade (alt und neu)
$addInPathOld = "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin"
$addInPathNew = "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in"
$addInFolders = @()
if (Test-Path $addInPathOld) {
    $addInFolders += Get-ChildItem $addInPathOld -Directory -ErrorAction SilentlyContinue
}
if (Test-Path $addInPathNew) {
    $addInFolders += Get-ChildItem $addInPathNew -Directory -ErrorAction SilentlyContinue
}
if ($addInFolders) {
    $latestFolder = ($addInFolders | Sort-Object Name -Descending)[0]
    Log "Add-in erfolgreich installiert - Ordner gefunden: $($latestFolder.FullName)"
} else {
    Log "WARNUNG: Add-in Ordner nicht gefunden in $addInPathOld oder $addInPathNew"
    # Pruefe auch Program Files
    $progFilesPath = "C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in"
    if (Test-Path $progFilesPath) {
        Log "Add-in in Program Files gefunden: $progFilesPath"
    }
}

foreach ($p in @("HKCU:\Software\Microsoft\Office\Teams","HKLM:\SOFTWARE\Microsoft\Office\Teams","HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Teams")) {
    if (-not (Test-Path $p)) { New-Item $p -Force -EA SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $p -Name "RegisterAsOfficeChatApp" -Value 1 -Type DWord -EA SilentlyContinue
}
$addinPaths = @("HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect","HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect","HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect")
foreach ($p in $addinPaths) {
    if (-not (Test-Path $p)) { New-Item $p -Force -EA SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $p -Name "LoadBehavior" -Value 3 -Type DWord -EA SilentlyContinue
    Set-ItemProperty -Path $p -Name "FriendlyName" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -Type String -EA SilentlyContinue
    Set-ItemProperty -Path $p -Name "Description" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -Type String -EA SilentlyContinue
}
Log "Registry (RegisterAsOfficeChatApp + LoadBehavior) gesetzt"

# DoNotDisableAddinList erstellen um zu verhindern dass Outlook das Add-in deaktiviert
$doNotDisablePath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"
if (-not (Test-Path $doNotDisablePath)) {
    New-Item $doNotDisablePath -Force | Out-Null
}
Set-ItemProperty -Path $doNotDisablePath -Name "TeamsAddin.FastConnect" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Log "DoNotDisableAddinList gesetzt"

# DLLs registrieren - beide moeglichen Pfade pruefen
$addInPaths = @(
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in",
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
    "C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in",
    "C:\Program Files (x86)\Microsoft\TeamsMeetingAddin"
)
$dllFound = $false
foreach ($basePath in $addInPaths) {
    if (Test-Path $basePath) {
        $folders = Get-ChildItem $basePath -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($folders) {
            $latest = $folders[0].FullName
            $dll64 = "$latest\x64\Microsoft.Teams.AddinLoader.dll"
            $dll86 = "$latest\x86\Microsoft.Teams.AddinLoader.dll"
            
            if (Test-Path $dll64) {
                Log "Registriere x64 DLL: $dll64"
                $proc = Start-Process regsvr32 -ArgumentList "/s `"$dll64`"" -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Log "x64 DLL erfolgreich registriert"
                    $dllFound = $true
                } else {
                    Log "WARNUNG: x64 DLL Registrierung fehlgeschlagen (ExitCode: $($proc.ExitCode))"
                }
            }
            
            if (Test-Path $dll86) {
                Log "Registriere x86 DLL: $dll86"
                $proc = Start-Process regsvr32 -ArgumentList "/s `"$dll86`"" -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Log "x86 DLL erfolgreich registriert"
                    $dllFound = $true
                } else {
                    Log "WARNUNG: x86 DLL Registrierung fehlgeschlagen (ExitCode: $($proc.ExitCode))"
                }
            }
            
            if (Test-Path $dll64) {
                $regPath = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
                if (-not (Test-Path $regPath)) {
                    New-Item $regPath -Force | Out-Null
                }
                Set-ItemProperty -Path $regPath -Name "Description" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -Type String -ErrorAction SilentlyContinue

                $manifest64 = $null
                $candidate = "$dll64.manifest"
                if (Test-Path $candidate) {
                    $manifest64 = $candidate
                } else {
                    $dllDir = Split-Path $dll64 -Parent
                    $m = Get-ChildItem $dllDir -Filter "*.dll.manifest" -File -EA SilentlyContinue | Select-Object -First 1
                    if ($m) { $manifest64 = $m.FullName }
                }

                if ($manifest64) {
                    Set-ItemProperty -Path $regPath -Name "Manifest" -Value $manifest64 -Type String -ErrorAction SilentlyContinue
                    Log "Add-in Registry (inkl. Manifest) gesetzt: $manifest64"
                } else {
                    if (Get-ItemProperty -Path $regPath -Name "Manifest" -EA SilentlyContinue) { Remove-ItemProperty -Path $regPath -Name "Manifest" -EA SilentlyContinue }
                    Log "Add-in Registry (ohne Manifest) gesetzt: $dll64"
                }
            }
            break
        }
    }
}

if (-not $dllFound) {
    Log "WARNUNG: DLLs nicht gefunden - Add-in moeglicherweise nicht installiert (part3 startet Outlook/Teams neu)"
}

Log "=== USER-Teil fertig - part3 fuehrt ggf. MSI-Installation und Outlook-Neustart durch ==="