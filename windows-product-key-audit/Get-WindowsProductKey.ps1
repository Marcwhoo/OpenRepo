# Reads the Windows product key and license type from WMI/SoftwareLicensingService.
# Appends the result to C:\EDV\UpgradeLogs\WindowsKey.log
# Useful before in-place upgrades to verify activation type and re-activation requirements.

$logFile = "C:\EDV\UpgradeLogs\WindowsKey.log"
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force -ErrorAction SilentlyContinue | Out-Null

function Get-WindowsProductKey {
    try {
        $wmi = Get-WmiObject -Query "SELECT * FROM SoftwareLicensingService"
        $key = $wmi.OA3xOriginalProductKey
        if (-not $key) {
            $key = (Get-CimInstance -ClassName SoftwareLicensingProduct |
                    Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*Pro*" } |
                    Select-Object -First 1).ProductKeyId
        }
        return $key ?? "No product key found"
    } catch {
        return "Error reading product key: $_"
    }
}

function Get-LicenseType {
    try {
        $description = (Get-WmiObject -Query "SELECT * FROM SoftwareLicensingService").Description
        $note = ""

        $type = switch -Regex ($description) {
            "OEM.*SLP"    { "OEM (System Builder / OEI)" }
            "OEM"         { "OEM (Hersteller)" }
            "VOLUME_MAK"  { $note = "Re-activation required (MAK key needed)."; "Volume (MAK)" }
            "VOLUME_KMS"  { $note = "Re-activation required (KMS server connection needed)."; "Volume (KMS)" }
            "RETAIL"      { $note = "Re-activation may be required."; "Retail" }
            "ESD"         { $note = "Re-activation may be required."; "ESD (Electronic Software Distribution)" }
            "GGK"         { "Get Genuine Kit (GGK)" }
            default       { $note = "License type unclear - manual activation check required."; "Unknown" }
        }

        # Secondary check for digital ESD license
        if (Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.LicenseIsAddon -eq $true -and $_.Name -like "*Windows*Pro*" }) {
            $type = "ESD (Electronic Software Distribution)"
            $note = "Re-activation may be required."
        }

        return [PSCustomObject]@{ LicenseType = $type; ReactivationNote = $note }
    } catch {
        return [PSCustomObject]@{ LicenseType = "Error: $_"; ReactivationNote = "Manual check required." }
    }
}

$key         = Get-WindowsProductKey
$licenseInfo = Get-LicenseType

@"
Windows Product Key Information
---------------------------------
Date:          $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
Computer:      $env:COMPUTERNAME
Domain:        $((Get-WmiObject Win32_ComputerSystem).Domain)
Product Key:   $key
License Type:  $($licenseInfo.LicenseType)
$($licenseInfo.ReactivationNote)
---------------------------------
"@ | Out-File -FilePath $logFile -Encoding UTF8 -Append

Write-Host "Logged to: $logFile"
