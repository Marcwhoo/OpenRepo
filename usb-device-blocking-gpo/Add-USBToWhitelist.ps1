<#
.SYNOPSIS
    Listet angeschlossene Wechselmedien auf, Auswahl welche whitelistet werden sollen.
    Verwendet NUR die modell-spezifische Hardware-ID (InstanceId mit Ven/Prod/Rev).
    Erkennt USBSTOR und SCSI (UAS) - funktioniert auch auf Admin-PCs.
    Auf Admin-PC ausfuehren.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$GpoName = "Wechselmedien verweigern",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# NUR modell-spezifische ID (InstanceId mit Ven/Prod/Rev) - verhindert dass andere SanDisk-Modelle erlaubt werden
# Device Installation Restrictions kann case-sensitiv matchen - exakte Case + Mixed-Case (Test-Client/Client) hinzufuegen
function Get-MixedCaseId {
    param([string]$id)
    if ($id -notmatch '&') { return $id }
    $parts = $id -split '\\', 2
    $segments = $parts[1] -split '&'
    $out = @()
    foreach ($s in $segments) {
        if ($s -match '^([A-Z]+)_(.+)$') {
            $p = $Matches[1].Substring(0,1) + $Matches[1].Substring(1).ToLowerInvariant()
            $val = $Matches[2]
            $v = $val.Substring(0,1).ToUpperInvariant() + $val.Substring(1).ToLowerInvariant()
            if ($val -eq 'UDISK') { $v = 'UDisk' }
            $out += "${p}_$v"
        } else {
            $out += $s.Substring(0,1) + $s.Substring(1).ToLowerInvariant()
        }
    }
    return "$($parts[0])\$($out -join '&')"
}
function Get-DeviceHardwareIds {
    param([object]$Dev)
    $ids = [System.Collections.Generic.HashSet[string]]::new()
    $hwId = $Dev.InstanceId.Substring(0, $Dev.InstanceId.LastIndexOf('\'))
    if (($hwId -like "USBSTOR\*" -or $hwId -like "SCSI\*") -and $hwId -match '&') {
        [void]$ids.Add($hwId)
        [void]$ids.Add($hwId.ToUpperInvariant())
        [void]$ids.Add((Get-MixedCaseId $hwId))
        # SCSI (UAS) und USBSTOR (BOT) - gleicher Stick kann je PC unterschiedlich erscheinen
        if ($hwId -like "SCSI\*") {
            $usbstor = $hwId -replace '^SCSI\\', 'USBSTOR\'
            if (-not $usbstor -match '&REV_') { $usbstor += '&REV_1.00' }
            [void]$ids.Add($usbstor)
            [void]$ids.Add($usbstor.ToUpperInvariant())
            [void]$ids.Add((Get-MixedCaseId $usbstor))
        } elseif ($hwId -like "USBSTOR\*" -and $hwId -match '&PROD_') {
            $scsi = $hwId -replace '&REV_[^&]+$', ''
            $scsi = $scsi -replace '^USBSTOR\\', 'SCSI\'
            [void]$ids.Add($scsi)
            [void]$ids.Add($scsi.ToUpperInvariant())
            [void]$ids.Add((Get-MixedCaseId $scsi))
        }
    }
    return [string[]]$ids
}

# USB-Storage: USBSTOR (klassisch) und SCSI (UAS - z.B. Admin-PCs). NVMe/ATA ausschliessen
$devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.InstanceId -like "USBSTOR*" -or ($_.InstanceId -like "SCSI\DISK*" -and $_.InstanceId -match 'VEN__USB')) -and
        $_.Status -eq "OK" -and
        $_.InstanceId -notmatch 'VEN_NVME|VEN_ATA'
    }

if (-not $devices) {
    Write-Warning "Keine Wechselmedien angeschlossen. Geraet einstecken und erneut ausfuehren."
    exit 1
}

$deviceList = @()
foreach ($dev in $devices) {
    $hwIds = Get-DeviceHardwareIds -Dev $dev
    if ($hwIds.Count -gt 0) {
        $deviceList += [PSCustomObject]@{
            FriendlyName = $dev.FriendlyName
            HardwareIds  = $hwIds
        }
    }
}

$deviceList = @($deviceList | Sort-Object FriendlyName | Group-Object { $_.HardwareIds[0] } | ForEach-Object { $_.Group[0] })
if (-not $deviceList) {
    Write-Warning "Hardware-IDs konnten nicht ermittelt werden."
    exit 1
}

Write-Host "`nAngeschlossene Wechselmedien:" -ForegroundColor Cyan
for ($i = 0; $i -lt $deviceList.Count; $i++) {
    Write-Host "  [$($i+1)] $($deviceList[$i].FriendlyName)"
    $deviceList[$i].HardwareIds | ForEach-Object { Write-Host "      $_" }
}

$selected = @()
if ($deviceList.Count -eq 1) {
    $antwort = Read-Host "`nGeraet whitelisten? (J/N)"
    if ($antwort -match "^[JjYy]") {
        $selected = $deviceList
    }
} else {
    Write-Host ""
    $eingabe = Read-Host "Nummern zum Whitelisten eingeben (z.B. 1,3 oder 1-3 oder alle)"
    if ($eingabe -match "^(?i)alle?$") {
        $selected = $deviceList
    } elseif ($eingabe) {
        $nummern = $eingabe -split "[,;\s]+" | ForEach-Object { $_.Trim() }
        foreach ($n in $nummern) {
            if ($n -match "(\d+)-(\d+)") {
                $von = [int]$Matches[1]; $bis = [int]$Matches[2]
                for ($j = $von; $j -le $bis; $j++) {
                    if ($j -ge 1 -and $j -le $deviceList.Count) {
                        $selected += $deviceList[$j-1]
                    }
                }
            } elseif ($n -match "^\d+$" -and [int]$n -ge 1 -and [int]$n -le $deviceList.Count) {
                $selected += $deviceList[[int]$n - 1]
            }
        }
    }
}

if (-not $selected) {
    Write-Host "Keine Auswahl. Abbruch."
    exit 0
}

$hardwareIds = @($selected | ForEach-Object { $_.HardwareIds } | ForEach-Object { $_ })
$hardwareIds = $hardwareIds | Sort-Object
Write-Host "`nAusgewaehlt (modell-spezifisch):" -ForegroundColor Green
$hardwareIds | ForEach-Object { Write-Host "  $_" }

if ($WhatIf) {
    Write-Host "`n(WhatIf - keine GPO-Aenderung)"
    exit 0
}

# GPO
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Warning "GroupPolicy-Modul fehlt (RSAT)."
    exit 1
}

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    Write-Warning "GPO '$GpoName' nicht gefunden."
    exit 1
}

# NICHT AllowDenyLayered=1 setzen - sonst wird DenyUnspecified ignoriert (Microsoft-Doku)
$restrictKey = "HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
$allowKey = "$restrictKey\AllowDeviceIDs"

$existing = @()
try {
    $vals = Get-GPRegistryValue -Name $GpoName -Key $allowKey -ErrorAction Stop
    $existing = @($vals | Where-Object { $_.ValueName -match "^\d+$" } | ForEach-Object { $_.Value })
} catch { }

$toAdd = $hardwareIds | Where-Object { $_ -notin $existing }
if (-not $toAdd) {
    Write-Host "`nAlle IDs der ausgewaehlten Geraete sind bereits in der Whitelist."
    exit 0
}

$allIds = @($existing) + @($toAdd)
for ($i = 0; $i -lt $allIds.Count; $i++) {
    Set-GPRegistryValue -Name $GpoName -Key $allowKey -ValueName ($i + 1).ToString() -Value $allIds[$i] -Type String
}

Write-Host "`n$($toAdd.Count) ID(s) zur Whitelist hinzugefuegt. Gesamt: $($allIds.Count)"
Write-Host "GPO aktualisiert. gpupdate /force auf Clients."
Write-Host "`nHinweis: Nur dieses Modell erlaubt (Ven/Prod/Rev). Andere SanDisk-Modelle bleiben blockiert."
Write-Host "Falls zuvor generische IDs drin waren: Remove-USBFromWhitelist.ps1 ausfuehren, Whitelist leeren, dann neu hinzufuegen."