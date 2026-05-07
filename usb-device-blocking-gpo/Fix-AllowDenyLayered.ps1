# Whitelist-Konfiguration: AllowDenyLayered=0 damit DenyUnspecified greift
# AllowDeviceIDs=1 AKTIVIERT die Whitelist (ohne diesen DWORD wird die Liste ignoriert!)
# Bei AllowDenyLayered=1 wird DenyUnspecified IGNORIERT -> alle Geraete werden erlaubt
param([string]$GpoName = "Wechselmedien verweigern")

$key = "HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
Get-GPO -Name $GpoName -ErrorAction Stop | Out-Null
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "AllowDenyLayered" -Value 0 -Type DWord
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "DenyUnspecified" -Value 1 -Type DWord
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "DenyRemovableDevices" -Value 0 -Type DWord
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "AllowDeviceIDs" -Value 1 -Type DWord
Write-Host "AllowDenyLayered=0, DenyUnspecified=1, DenyRemovableDevices=0, AllowDeviceIDs=1 gesetzt. gpupdate /force + Neustart."
