# Analyse-Script fuer Remote-PC - Teams Meeting Add-in Status
# Fuehrt nur Analysen durch, keine Aenderungen

param(
    [string]$ComputerName = "<CLIENT-HOSTNAME>",
    [string]$IPAddress = "<IP-ADDRESS>"
)

$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsAddin-Analyse.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Log { 
    param($msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "${timestamp}: $msg"
    Write-Host $logMsg
    Add-Content -Path $logFile -Value $logMsg
}

Log "=== Teams Meeting Add-in Analyse startet ==="
Log "Computer: $ComputerName / $IPAddress"

# Versuche Verbindung zum Remote-PC
$targetPC = $ComputerName
if (-not (Test-Connection -ComputerName $targetPC -Count 1 -Quiet)) {
    Log "WARNUNG: Verbindung zu $targetPC fehlgeschlagen, versuche $IPAddress"
    $targetPC = $IPAddress
    if (-not (Test-Connection -ComputerName $targetPC -Count 1 -Quiet)) {
        Log "FEHLER: Keine Verbindung moeglich zu $ComputerName oder $IPAddress"
        exit 1
    }
}

Log "Verbindung erfolgreich zu: $targetPC"

# Sammle Informationen per Remote-PowerShell
$scriptBlock = {
    $results = @{}
    
    # 1. Office Installationstyp
    $results.OfficeType = "Unknown"
    $results.OfficeClickToRun = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration") {
        $results.OfficeType = "Click-to-Run"
        $results.OfficeClickToRun = $true
    } elseif (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\16.0") {
        $results.OfficeType = "MSI"
    }
    
    # 2. Teams Installation
    $results.TeamsAppX = $null
    $teamsApp = Get-AppxPackage MSTeams -ErrorAction SilentlyContinue
    if ($teamsApp) {
        $results.TeamsAppX = @{
            Name = $teamsApp.Name
            Version = $teamsApp.Version
            InstallLocation = $teamsApp.InstallLocation
        }
    }
    
    # 3. Teams Meeting Add-in in Uninstall Registry
    $results.AddinUninstall = @()
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($base in $uninstallKeys) {
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($props -and ($props.DisplayName -like "*Teams Meeting Add-in*" -or $props.DisplayName -like "*TeamsAddin*" -or $props.DisplayName -like "*Teams*Add*in*")) {
                    $results.AddinUninstall += @{
                        Path = $_.PSPath
                        GUID = $_.PSChildName
                        DisplayName = $props.DisplayName
                        InstallDate = $props.InstallDate
                        InstallSource = $props.InstallSource
                        Publisher = $props.Publisher
                        Version = $props.Version
                    }
                }
            }
        }
    }
    
    # 4. Registry Add-in Eintraege
    $results.AddinRegistry = @()
    $regPaths = @(
        "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
        "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            $results.AddinRegistry += @{
                Path = $regPath
                LoadBehavior = $props.LoadBehavior
                FriendlyName = $props.FriendlyName
                Description = $props.Description
                Manifest = $props.Manifest
            }
        }
    }
    
    # 5. Teams Registry
    $results.TeamsRegistry = @()
    $teamsRegPaths = @(
        "HKCU:\Software\Microsoft\Office\Teams",
        "HKLM:\SOFTWARE\Microsoft\Office\Teams",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Teams"
    )
    foreach ($regPath in $teamsRegPaths) {
        if (Test-Path $regPath) {
            $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            $results.TeamsRegistry += @{
                Path = $regPath
                RegisterAsOfficeChatApp = $props.RegisterAsOfficeChatApp
            }
        }
    }
    
    # 6. DisabledItem Eintraege
    $results.DisabledItems = @()
    $resiliencyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency"
    if (Test-Path $resiliencyPath) {
        Get-ChildItem $resiliencyPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.DisabledItem -like "*TeamsAddin*") {
                $results.DisabledItems += @{
                    Path = $_.PSPath
                    DisabledItem = $props.DisabledItem
                }
            }
        }
    }
    
    # 7. DoNotDisableAddinList
    $results.DoNotDisable = $null
    $doNotDisablePath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"
    if (Test-Path $doNotDisablePath) {
        $props = Get-ItemProperty $doNotDisablePath -ErrorAction SilentlyContinue
        $results.DoNotDisable = $props
    }
    
    # 8. Add-in Installationspfade
    $results.AddinPaths = @()
    $pathsToCheck = @(
        "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in",
        "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
        "C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in",
        "C:\Program Files (x86)\Microsoft\TeamsMeetingAddin",
        "C:\Program Files\Microsoft\TeamsMeetingAdd-in",
        "C:\Program Files\Microsoft\TeamsMeetingAddin"
    )
    foreach ($path in $pathsToCheck) {
        if (Test-Path $path) {
            $folders = Get-ChildItem $path -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            if ($folders) {
                $latest = $folders[0]
                $dll64 = "$($latest.FullName)\x64\Microsoft.Teams.AddinLoader.dll"
                $dll86 = "$($latest.FullName)\x86\Microsoft.Teams.AddinLoader.dll"
                $results.AddinPaths += @{
                    BasePath = $path
                    LatestFolder = $latest.FullName
                    Version = $latest.Name
                    DLL64Exists = (Test-Path $dll64)
                    DLL86Exists = (Test-Path $dll86)
                    DLL64Path = $dll64
                    DLL86Path = $dll86
                }
            }
        }
    }
    
    # 9. Windows Installer Datenbank Eintraege
    $results.InstallerDB = @()
    $knownGuids = @(
        "{0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}",
        "{731F6BAA-A986-45C4-BCF4-724D65C1B15C}",
        "{A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91}"
    )
    foreach ($guid in $knownGuids) {
        $guidClean = $guid -replace '[{}]', '' -replace '-', ''
        if ($guidClean.Length -eq 32) {
            $chars = $guidClean.Substring(0,8).ToCharArray()
            [array]::Reverse($chars)
            $result = -join $chars
            $chars = $guidClean.Substring(8,4).ToCharArray()
            [array]::Reverse($chars)
            $result += -join $chars
            $chars = $guidClean.Substring(12,4).ToCharArray()
            [array]::Reverse($chars)
            $result += -join $chars
            for ($i = 16; $i -lt 28; $i += 2) {
                $pair = $guidClean.Substring($i,2)
                $result += $pair[1] + $pair[0]
            }
            $crypticGuid = $result.ToUpper()
            
            $installerPaths = @(
                "HKCR:\Installer\Products\$crypticGuid",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$crypticGuid"
            )
            foreach ($instPath in $installerPaths) {
                if (Test-Path $instPath) {
                    $results.InstallerDB += @{
                        GUID = $guid
                        CrypticGUID = $crypticGuid
                        Path = $instPath
                    }
                }
            }
        }
    }
    
    # 10. AlwaysInstallElevated
    $results.AlwaysInstallElevated = @()
    $aiePaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer",
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer"
    )
    foreach ($aiePath in $aiePaths) {
        if (Test-Path $aiePath) {
            $props = Get-ItemProperty $aiePath -Name AlwaysInstallElevated -ErrorAction SilentlyContinue
            if ($props -and $props.AlwaysInstallElevated) {
                $results.AlwaysInstallElevated += @{
                    Path = $aiePath
                    Value = $props.AlwaysInstallElevated
                }
            }
        }
    }
    
    # 11. Laufende Prozesse
    $results.Processes = @()
    $processes = @("OUTLOOK", "Teams", "ms-teams", "msiexec")
    foreach ($procName in $processes) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            $results.Processes += @{
                Name = $procName
                Count = $procs.Count
                PIDs = $procs.Id
            }
        }
    }
    
    # 12. MSI-Datei im Teams Package
    $results.MSIFile = $null
    if ($teamsApp -and $teamsApp.InstallLocation) {
        $msiPath = "$($teamsApp.InstallLocation)\MicrosoftTeamsMeetingAddinInstaller.msi"
        if (Test-Path $msiPath) {
            $msiFile = Get-Item $msiPath -ErrorAction SilentlyContinue
            $results.MSIFile = @{
                Path = $msiPath
                Exists = $true
                Size = $msiFile.Length
                LastWriteTime = $msiFile.LastWriteTime
            }
        } else {
            $results.MSIFile = @{ Exists = $false }
        }
    }
    
    # 13. WMI Products
    $results.WMIProducts = @()
    try {
        $products = Get-WmiObject Win32_Product | Where-Object {
            $_.Name -like "*Teams Meeting Add-in*" -or 
            $_.Name -like "*TeamsAddin*" -or 
            $_.Name -like "*Teams*Add*in*"
        }
        foreach ($product in $products) {
            $results.WMIProducts += @{
                Name = $product.Name
                GUID = $product.IdentifyingNumber
                Version = $product.Version
            }
        }
    } catch {
        $results.WMIError = $_.Exception.Message
    }
    
    # 14. Log-Dateien
    $results.LogFiles = @()
    $logDir = "C:\EDV\Logs"
    if (Test-Path $logDir) {
        $logFiles = Get-ChildItem $logDir -Filter "*Teams*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        foreach ($logFile in $logFiles) {
            $results.LogFiles += @{
                Name = $logFile.Name
                Path = $logFile.FullName
                Size = $logFile.Length
                LastWriteTime = $logFile.LastWriteTime
            }
        }
    }
    
    return $results
}

try {
    Log "Starte Remote-Analyse auf $targetPC"
    $results = $null
    
    # Versuche zuerst Invoke-Command (WinRM)
    try {
        $results = Invoke-Command -ComputerName $targetPC -ScriptBlock $scriptBlock -ErrorAction Stop
        Log "Remote-Analyse erfolgreich ueber WinRM"
    } catch {
        Log "WinRM fehlgeschlagen: $($_.Exception.Message)"
        Log "Versuche alternative Methode ueber WMI..."
        
        # Alternative: WMI Invoke-WmiMethod
        try {
            $scriptBlockString = $scriptBlock.ToString()
            $encodedScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlockString))
            $results = Invoke-WmiMethod -ComputerName $targetPC -Class Win32_Process -Name Create -ArgumentList "powershell.exe -EncodedCommand $encodedScript" -ErrorAction Stop
            Log "WMI-Methode gestartet, warte auf Ergebnisse..."
            Start-Sleep -Seconds 10
            
            # WMI kann nicht direkt Ergebnisse zurueckgeben, daher Fallback
            Log "WARNUNG: WMI kann keine direkten Ergebnisse zurueckgeben"
            Log "Bitte fuehre das Script lokal auf dem Remote-PC aus oder aktiviere WinRM"
            Log ""
            Log "ALTERNATIVE: Kopiere dieses Script auf den Remote-PC und fuehre es lokal aus"
            Log "Oder aktiviere WinRM mit: Enable-PSRemoting -Force (auf Remote-PC als Admin)"
            exit 1
        } catch {
            Log "Auch WMI-Methode fehlgeschlagen: $($_.Exception.Message)"
            Log ""
            Log "FEHLER: Keine Remote-Verbindung moeglich"
            Log "Moegliche Loesungen:"
            Log "1. Aktiviere WinRM auf Remote-PC: Enable-PSRemoting -Force (als Admin)"
            Log "2. Fuehre das Script lokal auf dem Remote-PC aus"
            Log "3. Nutze psexec oder andere Remote-Tools"
            exit 1
        }
    }
    
    # Ausgabe der Ergebnisse
    Log "=== ANALYSE-ERGEBNISSE ==="
    Log ""
    
    Log "1. Office Installationstyp: $($results.OfficeType)"
    Log ""
    
    if ($results.TeamsAppX) {
        Log "2. Teams AppX Package:"
        Log "   Name: $($results.TeamsAppX.Name)"
        Log "   Version: $($results.TeamsAppX.Version)"
        Log "   InstallLocation: $($results.TeamsAppX.InstallLocation)"
    } else {
        Log "2. Teams AppX Package: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.AddinUninstall.Count -gt 0) {
        Log "3. Teams Meeting Add-in in Uninstall Registry ($($results.AddinUninstall.Count) Eintraege):"
        foreach ($entry in $results.AddinUninstall) {
            Log "   GUID: $($entry.GUID)"
            Log "   DisplayName: $($entry.DisplayName)"
            Log "   InstallDate: $($entry.InstallDate)"
            Log "   InstallSource: $($entry.InstallSource)"
            Log "   Path: $($entry.Path)"
            Log "   ---"
        }
    } else {
        Log "3. Teams Meeting Add-in in Uninstall Registry: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.AddinRegistry.Count -gt 0) {
        Log "4. Add-in Registry Eintraege ($($results.AddinRegistry.Count) Eintraege):"
        foreach ($entry in $results.AddinRegistry) {
            Log "   Path: $($entry.Path)"
            Log "   LoadBehavior: $($entry.LoadBehavior)"
            Log "   FriendlyName: $($entry.FriendlyName)"
            Log "   Manifest: $($entry.Manifest)"
            Log "   ---"
        }
    } else {
        Log "4. Add-in Registry Eintraege: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.TeamsRegistry.Count -gt 0) {
        Log "5. Teams Registry Eintraege:"
        foreach ($entry in $results.TeamsRegistry) {
            Log "   Path: $($entry.Path)"
            Log "   RegisterAsOfficeChatApp: $($entry.RegisterAsOfficeChatApp)"
        }
    } else {
        Log "5. Teams Registry Eintraege: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.DisabledItems.Count -gt 0) {
        Log "6. DisabledItem Eintraege ($($results.DisabledItems.Count) Eintraege):"
        foreach ($entry in $results.DisabledItems) {
            Log "   Path: $($entry.Path)"
            Log "   DisabledItem: $($entry.DisabledItem)"
        }
    } else {
        Log "6. DisabledItem Eintraege: KEINE GEFUNDEN"
    }
    Log ""
    
    if ($results.DoNotDisable) {
        Log "7. DoNotDisableAddinList: VORHANDEN"
        $props = $results.DoNotDisable | Get-Member -MemberType NoteProperty
        foreach ($prop in $props) {
            Log "   $($prop.Name): $($results.DoNotDisable.$($prop.Name))"
        }
    } else {
        Log "7. DoNotDisableAddinList: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.AddinPaths.Count -gt 0) {
        Log "8. Add-in Installationspfade ($($results.AddinPaths.Count) Pfade):"
        foreach ($path in $results.AddinPaths) {
            Log "   BasePath: $($path.BasePath)"
            Log "   LatestFolder: $($path.LatestFolder)"
            Log "   Version: $($path.Version)"
            Log "   DLL64Exists: $($path.DLL64Exists)"
            Log "   DLL86Exists: $($path.DLL86Exists)"
            Log "   ---"
        }
    } else {
        Log "8. Add-in Installationspfade: NICHT GEFUNDEN"
    }
    Log ""
    
    if ($results.InstallerDB.Count -gt 0) {
        Log "9. Windows Installer Datenbank Eintraege ($($results.InstallerDB.Count) Eintraege):"
        foreach ($entry in $results.InstallerDB) {
            Log "   GUID: $($entry.GUID)"
            Log "   Path: $($entry.Path)"
        }
    } else {
        Log "9. Windows Installer Datenbank Eintraege: KEINE GEFUNDEN"
    }
    Log ""
    
    if ($results.AlwaysInstallElevated.Count -gt 0) {
        Log "10. AlwaysInstallElevated ($($results.AlwaysInstallElevated.Count) Eintraege):"
        foreach ($entry in $results.AlwaysInstallElevated) {
            Log "   Path: $($entry.Path)"
            Log "   Value: $($entry.Value)"
        }
    } else {
        Log "10. AlwaysInstallElevated: NICHT GESETZT"
    }
    Log ""
    
    if ($results.Processes.Count -gt 0) {
        Log "11. Laufende Prozesse:"
        foreach ($proc in $results.Processes) {
            Log "   $($proc.Name): $($proc.Count) Prozess(e) (PIDs: $($proc.PIDs -join ', '))"
        }
    } else {
        Log "11. Laufende Prozesse: KEINE RELEVANTEN GEFUNDEN"
    }
    Log ""
    
    if ($results.MSIFile) {
        if ($results.MSIFile.Exists) {
            Log "12. MSI-Datei im Teams Package:"
            Log "   Path: $($results.MSIFile.Path)"
            Log "   Size: $($results.MSIFile.Size) Bytes"
            Log "   LastWriteTime: $($results.MSIFile.LastWriteTime)"
        } else {
            Log "12. MSI-Datei im Teams Package: NICHT GEFUNDEN"
        }
    } else {
        Log "12. MSI-Datei im Teams Package: KONNTE NICHT GEPRUEFT WERDEN"
    }
    Log ""
    
    if ($results.WMIProducts.Count -gt 0) {
        Log "13. WMI Products ($($results.WMIProducts.Count) Produkte):"
        foreach ($product in $results.WMIProducts) {
            Log "   Name: $($product.Name)"
            Log "   GUID: $($product.GUID)"
            Log "   Version: $($product.Version)"
        }
    } else {
        Log "13. WMI Products: KEINE GEFUNDEN"
    }
    if ($results.WMIError) {
        Log "   WMI Fehler: $($results.WMIError)"
    }
    Log ""
    
    if ($results.LogFiles.Count -gt 0) {
        Log "14. Log-Dateien ($($results.LogFiles.Count) Dateien):"
        foreach ($logFile in $results.LogFiles) {
            Log "   $($logFile.Name) - $($logFile.Size) Bytes - $($logFile.LastWriteTime)"
        }
    } else {
        Log "14. Log-Dateien: KEINE GEFUNDEN"
    }
    Log ""
    
    Log "=== ANALYSE ABGESCHLOSSEN ==="
    Log "Vollstaendiger Log gespeichert in: $logFile"
    
} catch {
    Log "FEHLER bei Remote-Analyse: $($_.Exception.Message)"
    Log "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}
