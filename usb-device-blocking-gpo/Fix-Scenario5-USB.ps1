# Microsoft Scenario 5: DenyDeviceClasses (USB) + AllowDeviceIDs (Infrastruktur + Whitelist)
# ACHTUNG: USB-Storage nutzt DiskDrive-Klasse (4d36e967), NICHT USB-Klassen. Scenario 5 blockiert
# 36fc9e60 (Host/Hubs) und 88BAE032 (USBDevice) - USB-Sticks koennen trotzdem installiert werden.
# Nur als Alternative zu DenyUnspecified pruefbar. Auf DC ausfuehren (RSAT).
param([string]$GpoName = "Wechselmedien verweigern")

$key = "HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
$denyClassKey = "$key\DenyDeviceClasses"
$allowKey = "$key\AllowDeviceIDs"

# USB-Infrastruktur (Host, Hubs) - ohne diese funktionieren Tastatur/Maus nicht
$infraIds = @(
    "PCI\CC_0C03", "PCI\CC_0C0330", "PCI\VEN_8086", "PNP0CA1", "PNP0CA1&HOST",
    "USB\ROOT_HUB30", "USB\ROOT_HUB20", "USB\USB20_HUB"
)

# USB-Klassen blockieren
$usbClasses = @(
    "{36fc9e60-c465-11cf-8056-444553540000}",  # USB (Host, Hubs)
    "{88BAE032-5A81-49f0-BC3D-A4FF138216D6}"   # USBDevice
)

Get-GPO -Name $GpoName -ErrorAction Stop | Out-Null

# DenyDeviceClasses setzen
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "DenyDeviceClasses" -Value 1 -Type DWord
Set-GPRegistryValue -Name $GpoName -Key $denyClassKey -ValueName "1" -Value $usbClasses[0] -Type String
Set-GPRegistryValue -Name $GpoName -Key $denyClassKey -ValueName "2" -Value $usbClasses[1] -Type String

# Retroaktiv
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "DenyDeviceClassesRetroactive" -Value 1 -Type DWord

# Layered Mode (Allow uebersteuert Deny fuer spezifische Geraete)
Set-GPRegistryValue -Name $GpoName -Key $key -ValueName "AllowDenyLayered" -Value 1 -Type DWord

# Bestehende AllowDeviceIDs holen (Whitelist)
$existing = @()
try {
    $vals = Get-GPRegistryValue -Name $GpoName -Key $allowKey -ErrorAction Stop
    $existing = @($vals | Where-Object { $_.ValueName -match "^\d+$" } | ForEach-Object { $_.Value })
} catch { }

# Infrastruktur hinzufuegen (ohne Duplikate)
$allIds = $infraIds + ($existing | Where-Object { $_ -notin $infraIds })
$valueNames = 1..$allIds.Count | ForEach-Object { $_.ToString() }
$valuesToSet = @($allIds | ForEach-Object { [string]$_ })
Set-GPRegistryValue -Name $GpoName -Key $allowKey -ValueName $valueNames -Value $valuesToSet -Type String

Write-Host "Scenario 5: DenyDeviceClasses (USB) + AllowDeviceIDs (Infrastruktur + Whitelist) gesetzt."
Write-Host "AllowDenyLayered=1. gpupdate /force + Neustart. _run-clear.ps1 empfohlen vor Test."
