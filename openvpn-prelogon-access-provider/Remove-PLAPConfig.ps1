# Removes the OpenVPN PLAP registry entry and cleans up the local deployment files.
# Run this to undo the PLAP deployment (OpenVPN_PLAP_script_deploy).

function Remove-PlapRegistryEntry {
    param (
        [string]$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\PLAP",
        [string]$EntryName    = "OpenVPN Connect"
    )
    if (Test-Path -Path $RegistryPath) {
        $entry = Get-ItemProperty -Path $RegistryPath -Name $EntryName -ErrorAction SilentlyContinue
        if ($entry) {
            Remove-ItemProperty -Path $RegistryPath -Name $EntryName -Force -ErrorAction SilentlyContinue
        }
    }
}

Remove-PlapRegistryEntry
Remove-Item -Path "C:\EDV\ovpn-plap.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\EDV\VPN-plap-config (run as ADMIN).bat" -Force -ErrorAction SilentlyContinue
