# Disables Windows Developer Mode and sets the DenyDeviceIDs policy.
# Used to prevent installation of unapproved 3rd-party device drivers via Windows Update.
# Runs silently with no output or restart.

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
    -Name "AllowDevelopmentWithoutDevLicense" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

if (Get-Module -ListAvailable -Name WindowsDeveloperLicense) {
    Import-Module WindowsDeveloperLicense
    Unregister-WindowsDeveloperLicense -Force -ErrorAction SilentlyContinue
}

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions"

# Ensure the full registry path exists (New-Item only creates one level at a time)
$currentPath = $registryPath.Split('\')[0]
foreach ($part in $registryPath.Split('\') | Select-Object -Skip 1) {
    $currentPath = "$currentPath\$part"
    if (-not (Test-Path $currentPath)) {
        New-Item -Path $currentPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

try {
    $existing = Get-ItemProperty -Path $registryPath -Name "DenyDeviceIDs" -ErrorAction SilentlyContinue
    if ($existing -and $existing.DenyDeviceIDs -ne 1) {
        Set-ItemProperty -Path $registryPath -Name "DenyDeviceIDs" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    } elseif (-not $existing) {
        New-ItemProperty -Path $registryPath -Name "DenyDeviceIDs" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }
