# Fuegt Clear-USBSTOR-Enum.cmd als Startup-Script zur GPO hinzu
$gpoName = "Wechselmedien verweigern"
$gpo = Get-GPO -Name $gpoName
$domain = $gpo.DomainName
$guid = $gpo.Id.ToString()
$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$startupPath = "\\$domain\SYSVOL\$domain\Policies\$guid\Machine\Scripts\Startup"

if (-not (Test-Path $startupPath)) {
    New-Item $startupPath -ItemType Directory -Force | Out-Null
}

Copy-Item "$scriptDir\Clear-USBSTOR-Enum.cmd" -Destination $startupPath -Force
Copy-Item "$scriptDir\Clear-USBSTOR-Enum.ps1" -Destination $startupPath -Force

$scriptsIni = "\\$domain\SYSVOL\$domain\Policies\$guid\Machine\Scripts\scripts.ini"
$scriptsDir = Split-Path $scriptsIni
if (-not (Test-Path $scriptsDir)) { New-Item $scriptsDir -ItemType Directory -Force | Out-Null }
$content = @"
[Startup]
0CmdLine=Clear-USBSTOR-Enum.cmd
0Parameters=
"@
[System.IO.File]::WriteAllText($scriptsIni, $content, [System.Text.Encoding]::Unicode)

# GPO-Version erhoehen damit Clients aktualisieren
$gptPath = "\\$domain\SYSVOL\$domain\Policies\$guid\Machine"
$gptIni = "$gptPath\gpt.ini"
if (Test-Path $gptIni) {
    $gpt = Get-Content $gptIni -Raw
    if ($gpt -match 'Version=(\d+)') {
        $ver = [int]$Matches[1] + 1
        $gpt = $gpt -replace 'Version=\d+', "Version=$ver"
        Set-Content $gptIni $gpt -NoNewline
    }
}

# Alte falsche scripts.ini in Startup entfernen (lag vorher am falschen Ort)
$wrongIni = "$startupPath\scripts.ini"
if (Test-Path $wrongIni) { Remove-Item $wrongIni -Force }

Write-Host "Startup-Script eingebunden (scripts.ini in Machine\Scripts\). gpupdate /force + Neustart auf Clients."
