#Requires -RunAsAdministrator
# Sets ExcludeExplicitO365Endpoint=1 in Outlook AutoDiscover registry for ALL users.
# Prevents Outlook from using the O365 endpoint directly, forcing on-premise autodiscover.
# Also applies to .DEFAULT hive so new users get the setting automatically.

$registryPath  = "Software\Microsoft\Office\16.0\Outlook\AutoDiscover"
$registryName  = "ExcludeExplicitO365Endpoint"
$registryValue = 1

function Set-UserRegistry {
    param ([string]$UserSid)
    try {
        $hive = "HKEY_USERS\$UserSid\$registryPath"
        if (-not (Test-Path "Registry::$hive")) {
            New-Item -Path "Registry::$hive" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::$hive" -Name $registryName -Value $registryValue -Type DWord -Force
        Write-Host "Set for SID: $UserSid"
    } catch {
        Write-Warning "Failed for SID $UserSid`: $_"
    }
}

# Apply to all currently loaded user hives (S-1-5-21-* = domain users)
Get-ChildItem -Path "Registry::HKEY_USERS" |
    Where-Object { $_.PSChildName -match "^S-1-5-21" -and $_.PSChildName -notmatch "\.DEFAULT|Classes$" } |
    ForEach-Object { Set-UserRegistry -UserSid $_.PSChildName }

# Apply to .DEFAULT so future new users also get the setting
try {
    $defaultHive = "HKEY_USERS\.DEFAULT\$registryPath"
    if (-not (Test-Path "Registry::$defaultHive")) {
        New-Item -Path "Registry::$defaultHive" -Force | Out-Null
    }
    Set-ItemProperty -Path "Registry::$defaultHive" -Name $registryName -Value $registryValue -Type DWord -Force
    Write-Host "Set for .DEFAULT"
} catch {
    Write-Warning "Failed for .DEFAULT: $_"
}

Write-Host "Done."
