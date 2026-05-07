# TeamsFix_USER_Addin_Registry.ps1 - baramundi als USER
# Registriert Outlook-Add-in (Registry + DLL) und startet Teams/Outlook neu
# Wird nach part3.ps1 ausgefuehrt

$ErrorActionPreference = "Continue"
$logDir = "C:\EDV\Logs"
$logFile = "$logDir\TeamsFix.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
function Log { param($msg); Add-Content -Path $logFile -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): [USER $env:USERNAME] $msg" }

Log "=== USER Add-in Registry startet ==="

# SCHRITT 1: VSTO-Registry komplett loeschen (verhindert ClickOnceAddInDeploymentManager-Fehler)
Log "Loesche VSTO-Registry Eintraege..."
$vstoPath = "HKCU:\Software\Microsoft\VSTO"
if (Test-Path $vstoPath) {
    Get-ChildItem $vstoPath -Recurse -EA SilentlyContinue | ForEach-Object {
        $keyPath = $_.PSPath
        try {
            $props = Get-ItemProperty $keyPath -EA SilentlyContinue
            $propsStr = $props | Out-String
            if ($propsStr -like "*Teams*" -or $propsStr -like "*TeamsMeeting*") {
                Remove-Item $keyPath -Recurse -Force -EA SilentlyContinue
                Log "VSTO-Eintrag geloescht: $keyPath"
            }
        } catch { }
    }
}

# SCHRITT 2: ClickOnce-Cache loeschen (alte VSTO-Deployments)
Log "Loesche ClickOnce-Cache..."
$clickOnceCache = "$env:LOCALAPPDATA\Apps\2.0"
if (Test-Path $clickOnceCache) {
    Get-ChildItem $clickOnceCache -Recurse -Directory -EA SilentlyContinue | ForEach-Object {
        if ($_.Name -like "*teams*" -or $_.Name -like "*Teams*") {
            Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
            Log "ClickOnce-Cache geloescht: $($_.FullName)"
        }
    }
    Get-ChildItem $clickOnceCache -Recurse -File -EA SilentlyContinue | ForEach-Object {
        if ($_.Name -like "*teams*" -or $_.Name -like "*Teams*") {
            Remove-Item $_.FullName -Force -EA SilentlyContinue
            Log "ClickOnce-Datei geloescht: $($_.FullName)"
        }
    }
}

# SCHRITT 3: Add-in Pfad finden
$addinPaths = @(
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in",
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
    "C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in",
    "C:\Program Files (x86)\Microsoft\TeamsMeetingAddin"
)
$addinBase = $null
foreach ($p in $addinPaths) {
    if (Test-Path $p) {
        $addinBase = $p
        break
    }
}

if (-not $addinBase) {
    Log "FEHLER: Add-in Ordner nicht gefunden"
    Log "=== USER Add-in Registry abgeschlossen ==="
    exit 1
}

$folders = Get-ChildItem $addinBase -Directory -EA SilentlyContinue | Sort-Object Name -Descending

$dll64 = Join-Path $addinBase "x64\Microsoft.Teams.AddinLoader.dll"
$dll86 = Join-Path $addinBase "x86\Microsoft.Teams.AddinLoader.dll"

if (-not (Test-Path $dll64) -and $folders) {
    foreach ($f in $folders) {
        $test64 = Join-Path $f.FullName "x64\Microsoft.Teams.AddinLoader.dll"
        $test86 = Join-Path $f.FullName "x86\Microsoft.Teams.AddinLoader.dll"
        if (Test-Path $test64) {
            $dll64 = $test64
            if (Test-Path $test86) { $dll86 = $test86 }
            break
        }
    }
}

if (-not (Test-Path $dll64)) {
    Log "FEHLER: x64 DLL nicht gefunden (Basis: $addinBase)"
    Log "=== USER Add-in Registry abgeschlossen ==="
    exit 1
}

Log "Add-in DLLs gefunden: $dll64"

# SCHRITT 4: RegisterAsOfficeChatApp setzen
foreach ($p in @("HKCU:\Software\Microsoft\Office\Teams","HKLM:\SOFTWARE\Microsoft\Office\Teams","HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Teams")) {
    if (-not (Test-Path $p)) { New-Item $p -Force -EA SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $p -Name "RegisterAsOfficeChatApp" -Value 1 -Type DWord -EA SilentlyContinue
}

# SCHRITT 5: Add-in Registry setzen (NUR LoadBehavior, FriendlyName, Description - KEIN Manifest!)
$addinRegPaths = @(
    "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
)
foreach ($p in $addinRegPaths) {
    if (-not (Test-Path $p)) { New-Item $p -Force -EA SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $p -Name "LoadBehavior" -Value 3 -Type DWord -EA SilentlyContinue
    Set-ItemProperty -Path $p -Name "FriendlyName" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -Type String -EA SilentlyContinue
    Set-ItemProperty -Path $p -Name "Description" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -Type String -EA SilentlyContinue
    # Manifest LOESCHEN falls vorhanden (ist fuer VSTO, nicht fuer COM-Add-ins)
    Remove-ItemProperty -Path $p -Name "Manifest" -EA SilentlyContinue
}
Log "Registry (LoadBehavior=3, FriendlyName, Description) gesetzt - KEIN Manifest"

# SCHRITT 6: Resiliency/DisabledItems bereinigen
$resiliencyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency"
if (Test-Path $resiliencyPath) {
    Get-ChildItem $resiliencyPath -EA SilentlyContinue | ForEach-Object {
        if ($_.Name -eq "DoNotDisableAddinList") { return }
        try {
            $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
            $propsStr = $props | Out-String
            if ($propsStr -like "*TeamsAddin*" -or $propsStr -like "*Teams*") {
                Remove-Item $_.PSPath -Force -EA SilentlyContinue
                Log "Teams Add-in aus Resiliency entfernt: $($_.Name)"
            }
        } catch { }
    }
}

$doNotDisablePath = "$resiliencyPath\DoNotDisableAddinList"
if (-not (Test-Path $doNotDisablePath)) { New-Item $doNotDisablePath -Force | Out-Null }
Set-ItemProperty -Path $doNotDisablePath -Name "TeamsAddin.FastConnect" -Value 1 -Type DWord -EA SilentlyContinue
Log "DoNotDisableAddinList gesetzt"

# SCHRITT 7: COM-Registrierung pruefen (wird bereits in part3 als SYSTEM gemacht)
# regsvr32 als USER schlaegt mit ExitCode 5 fehl, daher hier nur Pruefung
$comRegPath = "HKLM:\SOFTWARE\Classes\TeamsAddin.FastConnect"
if (Test-Path $comRegPath) {
    Log "COM-Registrierung vorhanden (HKLM)"
} else {
    Log "WARNUNG: COM-Registrierung fehlt - part3 muss als SYSTEM laufen!"
}

# Legacy: Falls part3 nicht gelaufen ist, versuche trotzdem (wird wahrscheinlich fehlschlagen)
if (-not (Test-Path $comRegPath)) {
    Log "Versuche COM-Registrierung als User (wird wahrscheinlich fehlschlagen)..."
    $regsvr64 = "$env:SystemRoot\System32\regsvr32.exe"
    $p64 = Start-Process $regsvr64 -ArgumentList "/s `"$dll64`"" -Wait -PassThru -NoNewWindow
    if ($p64.ExitCode -eq 0) { Log "x64 DLL registriert" } 
    else { Log "HINWEIS: COM-Registrierung als User nicht moeglich (ExitCode: $($p64.ExitCode)) - das ist normal, part3 macht das als SYSTEM" }
}

if (Test-Path $dll86) {
    Log "x86 DLL vorhanden: $dll86"
}

# SCHRITT 8: Teams und Outlook neu starten
Log "Starte Teams und Outlook neu..."
$outlookExe = "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE"
if (-not (Test-Path $outlookExe)) { $outlookExe = "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE" }
if (Test-Path $outlookExe) {
    Stop-Process -Name Teams,ms-teams,OUTLOOK -Force -EA SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Process "explorer.exe" -ArgumentList "shell:appsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
    Start-Sleep -Seconds 15
    Start-Process $outlookExe
    Log "Outlook und Teams gestartet"
} else {
    Log "Outlook.exe nicht gefunden - bitte manuell neu starten"
}

Log "=== USER Add-in Registry abgeschlossen ==="
