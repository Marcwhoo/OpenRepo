#Requires -RunAsAdministrator
# Deletes all domain user profiles that are NOT currently logged in.
# Skips local accounts, system accounts, and the 'admin' profile.

Import-Module ActiveDirectory -ErrorAction SilentlyContinue
if (-not (Get-Module -Name ActiveDirectory)) {
    Write-Warning "ActiveDirectory module not available - domain user detection may be limited."
}

function Get-CurrentUser {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Get-LoggedOnUsers {
    $loggedOnSids = @()
    $sessions = qwinsta | Where-Object { $_ -match 'Aktiv' }
    foreach ($session in $sessions) {
        $sid = (Get-WmiObject -Class Win32_LogonSession | Where-Object { $_.LogonId -eq ($session -split '\s+')[3] }).LogonSid
        if ($sid) { $loggedOnSids += $sid }
    }
    return $loggedOnSids
}

function Is-DomainUser {
    param ($Sid)
    try {
        $sidObj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        $account = $sidObj.Translate([System.Security.Principal.NTAccount])
        return $account.Value -like '*\*'
    } catch {
        return $false
    }
}

Write-Host "Searching for inactive domain user profiles..." -ForegroundColor Green

$excludedProfiles = @('Administrator', 'Default', 'Public', 'defaultuser0', 'admin', (Get-CurrentUser).Split('\')[1])
$excludedSids = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')  # System, Local Service, Network Service

$profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$profiles = Get-ChildItem -Path $profileListPath | ForEach-Object { Get-ItemProperty -Path $_.PSPath }
$loggedOnSids = Get-LoggedOnUsers
$profilesToDelete = @()

foreach ($profile in $profiles) {
    $sid = $profile.PSChildName
    $profilePath = $profile.ProfileImagePath
    $userName = if ($profilePath) { Split-Path $profilePath -Leaf } else { "Unknown" }

    if ($excludedSids -contains $sid -or $excludedProfiles -contains $userName) {
        Write-Host "Skipping excluded: $userName ($sid)" -ForegroundColor Yellow
        continue
    }

    if (-not (Is-DomainUser -Sid $sid)) {
        Write-Host "Skipping local account: $userName ($sid)" -ForegroundColor Yellow
        continue
    }

    if ($loggedOnSids -contains $sid) {
        Write-Host "Skipping active session: $userName ($sid)" -ForegroundColor Yellow
        continue
    }

    $profilesToDelete += [PSCustomObject]@{
        UserName    = $userName
        SID         = $sid
        ProfilePath = $profilePath
    }
}

if ($profilesToDelete.Count -eq 0) {
    Write-Host "No inactive domain profiles found." -ForegroundColor Cyan
    exit
}

Write-Host "`nProfiles to delete:" -ForegroundColor Green
$profilesToDelete | Format-Table -Property UserName, SID, ProfilePath -AutoSize

foreach ($profile in $profilesToDelete) {
    Write-Host "Deleting: $($profile.UserName) ($($profile.SID))" -ForegroundColor Yellow

    try {
        $regPath = Join-Path $profileListPath $profile.SID
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Force -ErrorAction Stop
            Write-Host "Registry entry removed: $regPath" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to remove registry entry for $($profile.SID): $_"
    }

    try {
        if (Test-Path $profile.ProfilePath) {
            Remove-Item -Path $profile.ProfilePath -Recurse -Force -ErrorAction Stop
            Write-Host "Profile folder deleted: $($profile.ProfilePath)" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to delete profile folder $($profile.ProfilePath): $_"
    }
}

Write-Host "`nDone." -ForegroundColor Green
