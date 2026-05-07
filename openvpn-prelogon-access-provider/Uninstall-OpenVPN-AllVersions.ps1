# Silently uninstalls ALL versions of OpenVPN found in the registry.
# Only processes valid MSI GUIDs - skips non-MSI uninstall entries.

$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$openvpnPrograms = Get-ItemProperty $uninstallPaths |
    Where-Object { $_.DisplayName -like "*OpenVPN*" -and $_.UninstallString } |
    Select-Object DisplayName, DisplayVersion, PSChildName

if ($openvpnPrograms.Count -eq 0) {
    Write-Host "No OpenVPN installations found."
    exit
}

foreach ($program in $openvpnPrograms) {
    Write-Host "Uninstalling: $($program.DisplayName) $($program.DisplayVersion)"
    if ($program.PSChildName -match '^\{.*\}$') {
        Start-Process "msiexec.exe" -ArgumentList "/X$($program.PSChildName) /quiet /norestart" -Wait -NoNewWindow
    } else {
        Write-Host "Skipped (no MSI GUID): $($program.DisplayName)"
    }
}

Write-Host "Done."
