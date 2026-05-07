<#
.SYNOPSIS
    Option A: DiskDrive-Klasse zu AllowDeviceClasses hinzufuegen.
    Ermoeglicht USB-Stick-Treiberinstallation; Zugriff nur fuer User in "Wechselmedien erlauben".
    Auf Admin-PC mit RSAT ausfuehren.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$GpoName = "Wechselmedien verweigern",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$diskDriveGuid = "{4d36e967-e325-11ce-bfc1-08002be10318}"

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Warning "GroupPolicy-Modul fehlt (RSAT)."
    exit 1
}

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    Write-Warning "GPO '$GpoName' nicht gefunden."
    exit 1
}

$classKey = "HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions\AllowDeviceClasses"

$existing = @()
try {
    $vals = Get-GPRegistryValue -Name $GpoName -Key $classKey -ErrorAction Stop
    $existing = @($vals | Where-Object { $_.ValueName -match "^\d+$" } | ForEach-Object { $_.Value })
} catch { }

$hasDiskDrive = $existing | Where-Object { $_ -match "4d36e967" }
if ($hasDiskDrive) {
    Write-Host "DiskDrive bereits in AllowDeviceClasses. Keine Aenderung."
    exit 0
}

if ($WhatIf) {
    Write-Host "WhatIf: DiskDrive $diskDriveGuid wuerde als Eintrag $($existing.Count + 1) hinzugefuegt."
    exit 0
}

$nextNum = $existing.Count + 1
Set-GPRegistryValue -Name $GpoName -Key $classKey -ValueName $nextNum.ToString() -Value $diskDriveGuid -Type String

Write-Host "DiskDrive ($diskDriveGuid) zu AllowDeviceClasses hinzugefuegt."
Write-Host "gpupdate /force auf Clients, USB-Stick neu einstecken, Zugriff nur fuer Gruppe 'Wechselmedien erlauben'."
