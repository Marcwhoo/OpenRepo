# Analyse-Script fuer lokalen PC - Teams Meeting Add-in Status
# Fuehrt nur Analysen durch, keine Aenderungen
# Kann direkt auf dem Remote-PC ausgefuehrt werden
# Ausfuehrung: Rechtsklick > Mit PowerShell ausfuehren (als Admin empfohlen)

$ErrorActionPreference = "Continue"

$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsAddin-Analyse-Lokal.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# Loesche alte Log-Datei
if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }

function Log { 
    param($msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "${timestamp}: $msg"
    Write-Host $logMsg
    try {
        Add-Content -Path $logFile -Value $logMsg -ErrorAction Stop
    } catch {
        Write-Host "FEHLER beim Schreiben in Log: $($_.Exception.Message)"
    }
}

Log "=== Teams Meeting Add-in Analyse startet (Lokal) ==="
Log "Computer: $env:COMPUTERNAME"
Log "User: $env:USERNAME"
Log "Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log ""

$results = @{}
$scriptErrors = @()

# 1. Office Installationstyp
Log "Analysiere Office Installationstyp..."
try {
    $results.OfficeType = "Unknown"
    $results.OfficeClickToRun = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration") {
        $results.OfficeType = "Click-to-Run"
        $results.OfficeClickToRun = $true
    } elseif (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\16.0") {
        $results.OfficeType = "MSI"
    }
} catch {
    $scriptErrors += "Office Installationstyp: $($_.Exception.Message)"
}

# 2. Teams Installation
Log "Analysiere Teams Installation..."
try {
    $results.TeamsAppX = $null
    $teamsApp = Get-AppxPackage MSTeams -ErrorAction SilentlyContinue
    if ($teamsApp) {
        $results.TeamsAppX = @{
            Name = $teamsApp.Name
            Version = $teamsApp.Version
            InstallLocation = $teamsApp.InstallLocation
        }
    }
} catch {
    $scriptErrors += "Teams Installation: $($_.Exception.Message)"
}

# 3. Teams Meeting Add-in in Uninstall Registry
Log "Analysiere Uninstall Registry..."
try {
    $results.AddinUninstall = @()
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($base in $uninstallKeys) {
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
                try {
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
                } catch {
                    # Ignoriere einzelne Registry-Fehler
                }
            }
        }
    }
} catch {
    $scriptErrors += "Uninstall Registry: $($_.Exception.Message)"
}

# 4. Registry Add-in Eintraege
Log "Analysiere Add-in Registry Eintraege..."
try {
    $results.AddinRegistry = @()
    $regPaths = @(
        "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
        "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            try {
                $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                $results.AddinRegistry += @{
                    Path = $regPath
                    LoadBehavior = $props.LoadBehavior
                    FriendlyName = $props.FriendlyName
                    Description = $props.Description
                    Manifest = $props.Manifest
                }
            } catch {
                # Ignoriere einzelne Registry-Fehler
            }
        }
    }
} catch {
    $scriptErrors += "Add-in Registry: $($_.Exception.Message)"
}

# 5. Teams Registry
Log "Analysiere Teams Registry..."
try {
    $results.TeamsRegistry = @()
    $teamsRegPaths = @(
        "HKCU:\Software\Microsoft\Office\Teams",
        "HKLM:\SOFTWARE\Microsoft\Office\Teams",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Teams"
    )
    foreach ($regPath in $teamsRegPaths) {
        if (Test-Path $regPath) {
            try {
                $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                $results.TeamsRegistry += @{
                    Path = $regPath
                    RegisterAsOfficeChatApp = $props.RegisterAsOfficeChatApp
                }
            } catch {
                # Ignoriere einzelne Registry-Fehler
            }
        }
    }
} catch {
    $scriptErrors += "Teams Registry: $($_.Exception.Message)"
}

# 6. DisabledItem Eintraege
Log "Analysiere DisabledItem Eintraege..."
try {
    $results.DisabledItems = @()
    $resiliencyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency"
    if (Test-Path $resiliencyPath) {
        Get-ChildItem $resiliencyPath -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($props -and $props.DisabledItem -like "*TeamsAddin*") {
                    $results.DisabledItems += @{
                        Path = $_.PSPath
                        DisabledItem = $props.DisabledItem
                    }
                }
            } catch {
                # Ignoriere einzelne Registry-Fehler
            }
        }
    }
} catch {
    $scriptErrors += "DisabledItem Eintraege: $($_.Exception.Message)"
}

# 7. DoNotDisableAddinList
Log "Analysiere DoNotDisableAddinList..."
try {
    $results.DoNotDisable = $null
    $doNotDisablePath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"
    if (Test-Path $doNotDisablePath) {
        $props = Get-ItemProperty $doNotDisablePath -ErrorAction SilentlyContinue
        $results.DoNotDisable = $props
    }
} catch {
    $scriptErrors += "DoNotDisableAddinList: $($_.Exception.Message)"
}

# 8. Add-in Installationspfade
Log "Analysiere Add-in Installationspfade..."
try {
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
            try {
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
            } catch {
                # Ignoriere einzelne Pfad-Fehler
            }
        }
    }
} catch {
    $scriptErrors += "Add-in Installationspfade: $($_.Exception.Message)"
}

# 9. Windows Installer Datenbank Eintraege
Log "Analysiere Windows Installer Datenbank..."
try {
    $results.InstallerDB = @()
    $knownGuids = @(
        "{0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}",
        "{731F6BAA-A986-45C4-BCF4-724D65C1B15C}",
        "{A7AB73A3-CB10-4AA5-9D38-6AEFFBDE4C91}"
    )
    foreach ($guid in $knownGuids) {
        try {
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
        } catch {
            # Ignoriere einzelne GUID-Fehler
        }
    }
} catch {
    $scriptErrors += "Windows Installer Datenbank: $($_.Exception.Message)"
}

# 10. AlwaysInstallElevated
Log "Analysiere AlwaysInstallElevated..."
try {
    $results.AlwaysInstallElevated = @()
    $aiePaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer",
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer"
    )
    foreach ($aiePath in $aiePaths) {
        if (Test-Path $aiePath) {
            try {
                $props = Get-ItemProperty $aiePath -Name AlwaysInstallElevated -ErrorAction SilentlyContinue
                if ($props -and $props.AlwaysInstallElevated) {
                    $results.AlwaysInstallElevated += @{
                        Path = $aiePath
                        Value = $props.AlwaysInstallElevated
                    }
                }
            } catch {
                # Ignoriere einzelne Registry-Fehler
            }
        }
    }
} catch {
    $scriptErrors += "AlwaysInstallElevated: $($_.Exception.Message)"
}

# 11. Laufende Prozesse
Log "Analysiere laufende Prozesse..."
try {
    $results.Processes = @()
    $processes = @("OUTLOOK", "Teams", "ms-teams", "msiexec")
    foreach ($procName in $processes) {
        try {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($procs) {
                $results.Processes += @{
                    Name = $procName
                    Count = $procs.Count
                    PIDs = $procs.Id
                }
            }
        } catch {
            # Ignoriere einzelne Prozess-Fehler
        }
    }
} catch {
    $scriptErrors += "Laufende Prozesse: $($_.Exception.Message)"
}

# 12. MSI-Datei im Teams Package
Log "Analysiere MSI-Datei im Teams Package..."
try {
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
} catch {
    $scriptErrors += "MSI-Datei: $($_.Exception.Message)"
}

# 13. WMI Products
Log "Analysiere WMI Products (kann etwas dauern)..."
$results.WMIProducts = @()
try {
    $products = Get-WmiObject Win32_Product -ErrorAction SilentlyContinue | Where-Object {
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
    $scriptErrors += "WMI Products: $($_.Exception.Message)"
}

# 14. Log-Dateien
Log "Analysiere vorhandene Log-Dateien..."
try {
    $results.LogFiles = @()
    $logDirCheck = "C:\EDV\Logs"
    if (Test-Path $logDirCheck) {
        $logFilesFound = Get-ChildItem $logDirCheck -Filter "*Teams*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        foreach ($logFileItem in $logFilesFound) {
            $results.LogFiles += @{
                Name = $logFileItem.Name
                Path = $logFileItem.FullName
                Size = $logFileItem.Length
                LastWriteTime = $logFileItem.LastWriteTime
            }
        }
    }
} catch {
    $scriptErrors += "Log-Dateien: $($_.Exception.Message)"
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
    foreach ($logFileItem in $results.LogFiles) {
        Log "   $($logFileItem.Name) - $($logFileItem.Size) Bytes - $($logFileItem.LastWriteTime)"
    }
} else {
    Log "14. Log-Dateien: KEINE GEFUNDEN"
}
Log ""

if ($scriptErrors.Count -gt 0) {
    Log ""
    Log "=== FEHLER WAEHREND DER ANALYSE ==="
    foreach ($errMsg in $scriptErrors) {
        Log "  - $errMsg"
    }
    Log ""
}

Log ""
Log "=== ZUSAMMENFASSUNG ==="
Log "Office Typ: $($results.OfficeType)"
if ($results.TeamsAppX) {
    Log "Teams installiert: Ja (Version: $($results.TeamsAppX.Version))"
} else {
    Log "Teams installiert: NEIN"
}
Log "Add-in in Uninstall Registry: $($results.AddinUninstall.Count) Eintraege"
Log "Add-in Registry Eintraege: $($results.AddinRegistry.Count) Eintraege"
Log "DisabledItem Eintraege: $($results.DisabledItems.Count) Eintraege"
if ($results.DoNotDisable) {
    Log "DoNotDisableAddinList: VORHANDEN"
} else {
    Log "DoNotDisableAddinList: NICHT GEFUNDEN"
}
Log "Add-in Installationspfade: $($results.AddinPaths.Count) Pfade"
Log "Windows Installer DB Eintraege: $($results.InstallerDB.Count) Eintraege"
if ($results.MSIFile -and $results.MSIFile.Exists) {
    Log "MSI-Datei im Teams Package: VORHANDEN"
} else {
    Log "MSI-Datei im Teams Package: NICHT GEFUNDEN"
}
Log ""

Log "=== ANALYSE ABGESCHLOSSEN ==="
Log "Vollstaendiger Log gespeichert in: $logFile"
Log "Bitte diese Log-Datei zur weiteren Analyse bereitstellen"
Log ""
Write-Host ""
Write-Host "Analyse abgeschlossen! Log-Datei: $logFile" -ForegroundColor Green
Write-Host "Druecke eine Taste zum Beenden..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

