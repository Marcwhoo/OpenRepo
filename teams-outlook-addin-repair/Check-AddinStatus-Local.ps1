# Quick Check - Teams Add-in Status (lokal ausfuehren)
# Ausgabe wird in C:\EDV\Logs\AddinStatus.txt geschrieben

$outFile = "C:\EDV\Logs\AddinStatus.txt"
$logDir = "C:\EDV\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

$output = @()
$output += "=== Teams Add-in Status Check: $env:COMPUTERNAME / $env:USERNAME ==="
$output += "Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$output += ""

# 1. Add-in Registry (HKCU)
$addinPath = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
$output += "1. Add-in Registry (TeamsAddin.FastConnect):"
if (Test-Path $addinPath) {
    $props = Get-ItemProperty $addinPath -EA SilentlyContinue
    $output += "   Existiert: JA"
    $output += "   LoadBehavior: $($props.LoadBehavior) $(if($props.LoadBehavior -eq 3){'(OK)'}else{'(FALSCH)'})"
    $output += "   FriendlyName: $($props.FriendlyName)"
    $output += "   Manifest: $($props.Manifest) $(if($props.Manifest){'(WARNUNG!)'}else{'(OK-leer)'})"
} else {
    $output += "   Existiert: NEIN"
}

# 2. Add-in DLL
$output += ""
$output += "2. Add-in DLL:"
$dllPaths = @(
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in\x64\Microsoft.Teams.AddinLoader.dll",
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin\x64\Microsoft.Teams.AddinLoader.dll"
)
$dllFound = $false
foreach ($p in $dllPaths) {
    if (Test-Path $p) {
        $output += "   Existiert: JA"
        $output += "   Pfad: $p"
        $dllFound = $true
        break
    }
}
if (-not $dllFound) {
    $output += "   Existiert: NEIN"
}

# 3. COM Registration (HKCU + HKLM)
$output += ""
$output += "3. COM Registration:"
$clsidPaths = @(
    "HKCU:\Software\Classes\CLSID",
    "HKLM:\SOFTWARE\Classes\CLSID",
    "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID"
)
$comFound = @()
foreach ($base in $clsidPaths) {
    if (Test-Path $base) {
        Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
            if ($props.'(default)' -like "*Teams*" -or $props.'(default)' -like "*AddinLoader*") {
                $comFound += "$($_.PSPath) = $($props.'(default)')"
            }
        }
    }
}
if ($comFound.Count -gt 0) {
    $output += "   Gefunden: JA"
    $comFound | ForEach-Object { $output += "   $_" }
} else {
    $output += "   Gefunden: NEIN (oder nicht unter bekanntem Namen)"
}

# 4. RegisterAsOfficeChatApp
$output += ""
$output += "4. RegisterAsOfficeChatApp:"
$teamsPath = "HKCU:\Software\Microsoft\Office\Teams"
if (Test-Path $teamsPath) {
    $props = Get-ItemProperty $teamsPath -EA SilentlyContinue
    $output += "   Wert: $($props.RegisterAsOfficeChatApp) $(if($props.RegisterAsOfficeChatApp -eq 1){'(OK)'}else{'(FALSCH)'})"
} else {
    $output += "   Registry-Pfad existiert nicht"
}

# 5. HKLM Add-in Registry
$output += ""
$output += "5. HKLM Add-in Registry:"
$hklmPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
)
foreach ($p in $hklmPaths) {
    if (Test-Path $p) {
        $props = Get-ItemProperty $p -EA SilentlyContinue
        $output += "   $p"
        $output += "      LoadBehavior: $($props.LoadBehavior)"
    }
}

# 6. DisabledItems
$output += ""
$output += "6. Resiliency/DisabledItems:"
$resPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency"
if (Test-Path $resPath) {
    Get-ChildItem $resPath -EA SilentlyContinue | ForEach-Object {
        $output += "   Subkey: $($_.PSChildName)"
        $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        $props | Get-Member -MemberType NoteProperty | ForEach-Object {
            if ($_.Name -notlike "PS*") {
                $val = $props.$($_.Name)
                $output += "      $($_.Name) = $val"
            }
        }
    }
} else {
    $output += "   Resiliency-Pfad existiert nicht (OK)"
}

# 7. Teams Prozess
$output += ""
$output += "7. Teams Prozess:"
$teamsProc = Get-Process -Name "ms-teams","Teams" -EA SilentlyContinue
if ($teamsProc) {
    $output += "   Laeuft: JA"
    $teamsProc | ForEach-Object { $output += "   $($_.ProcessName) (PID: $($_.Id))" }
} else {
    $output += "   Laeuft: NEIN"
}

# 8. Outlook Prozess
$output += ""
$output += "8. Outlook Prozess:"
$outlookProc = Get-Process -Name "OUTLOOK" -EA SilentlyContinue
if ($outlookProc) {
    $output += "   Laeuft: JA (PID: $($outlookProc.Id))"
} else {
    $output += "   Laeuft: NEIN"
}

$output += ""
$output += "=== Check abgeschlossen ==="

# Ausgabe in Datei und Console
$output | Out-File $outFile -Encoding UTF8
$output | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Ergebnis gespeichert in: $outFile" -ForegroundColor Green
