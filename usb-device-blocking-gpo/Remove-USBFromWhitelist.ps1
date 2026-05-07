<#
.SYNOPSIS
    Listet gewhitelistete Wechselmedien aus der GPO auf, Auswahl welche entfernt werden sollen.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$GpoName = "Wechselmedien verweigern",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Warning "GroupPolicy-Modul fehlt (RSAT)."
    exit 1
}

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    Write-Warning "GPO '$GpoName' nicht gefunden."
    exit 1
}

$allowKey = "HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions\AllowDeviceIDs"

$whitelist = @()
try {
    $vals = Get-GPRegistryValue -Name $GpoName -Key $allowKey -ErrorAction Stop
    $whitelist = @($vals | Where-Object { $_.ValueName -match "^\d+$" } | Sort-Object { [int]$_.ValueName } | ForEach-Object { $_.Value })
} catch { }

if (-not $whitelist) {
    Write-Host "Whitelist ist leer. Keine Geraete zum Entfernen."
    exit 0
}

Write-Host "`nGewhitelistete Geraete:" -ForegroundColor Cyan
for ($i = 0; $i -lt $whitelist.Count; $i++) {
    Write-Host "  [$($i+1)] $($whitelist[$i])"
}

$toRemove = @()
if ($whitelist.Count -eq 1) {
    $antwort = Read-Host "`nGeraet aus Whitelist entfernen? (J/N)"
    if ($antwort -match "^[JjYy]") {
        $toRemove = $whitelist
    }
} else {
    Write-Host ""
    $eingabe = Read-Host "Nummern zum Entfernen eingeben (z.B. 1,3 oder 1-3 oder alle)"
    if ($eingabe -match "^(?i)alle?$") {
        $toRemove = $whitelist
    } elseif ($eingabe) {
        $nummern = $eingabe -split "[,;\s]+" | ForEach-Object { $_.Trim() }
        foreach ($n in $nummern) {
            if ($n -match "(\d+)-(\d+)") {
                $von = [int]$Matches[1]; $bis = [int]$Matches[2]
                for ($j = $von; $j -le $bis; $j++) {
                    if ($j -ge 1 -and $j -le $whitelist.Count) {
                        $toRemove += $whitelist[$j-1]
                    }
                }
            } elseif ($n -match "^\d+$" -and [int]$n -ge 1 -and [int]$n -le $whitelist.Count) {
                $toRemove += $whitelist[[int]$n - 1]
            }
        }
    }
}

if (-not $toRemove) {
    Write-Host "Keine Auswahl. Abbruch."
    exit 0
}

$toRemove = $toRemove | Select-Object -Unique
$remaining = $whitelist | Where-Object { $_ -notin $toRemove }
Write-Host "`nEntfernen:" -ForegroundColor Yellow
$toRemove | ForEach-Object { Write-Host "  $_" }

if ($WhatIf) {
    Write-Host "`n(WhatIf - keine Aenderung)"
    exit 0
}

if ($remaining.Count -eq 0) {
    Remove-GPRegistryValue -Name $GpoName -Key $allowKey -ErrorAction SilentlyContinue
    Write-Host "`nWhitelist geleert. Alle Geraete entfernt."
} else {
    $valueNames = 1..$remaining.Count | ForEach-Object { $_.ToString() }
    Set-GPRegistryValue -Name $GpoName -Key $allowKey -ValueName $valueNames -Value $remaining -Type String
    Write-Host "`n$($toRemove.Count) Geraet(e) entfernt. $($remaining.Count) verbleiben."
}

Write-Host "GPO aktualisiert. gpupdate /force auf Clients."
