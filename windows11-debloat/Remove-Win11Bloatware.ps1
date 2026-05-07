#Requires -RunAsAdministrator
# Removes bloatware apps, replaces the Start menu layout, and imports registry tweaks.
# Required files (deployed via baramundi from \\<BARAMUNDI-SERVER>\dip$\Apl\WindowsDebloat):
#   Appslist.txt   - one app name per line, lines starting with # are ignored
#   Start\start2.bin - custom Start menu layout binary
#   RegFiles\*.reg   - registry tweak files to import

$startMenuTemplate = "C:\EDV\debloat\Start\start2.bin"
$appsListPath      = "C:\EDV\debloat\Appslist.txt"
$regFilesPath      = "C:\EDV\debloat\RegFiles"

function Remove-Apps {
    param([string[]]$AppList)
    $winBuild = [System.Environment]::OSVersion.Version.Build
    foreach ($app in $AppList) {
        $pattern = "*$app*"
        try {
            if ($winBuild -ge 22000) {
                # Windows 11: remove for all users + deprovisioned
                Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
                Get-AppxProvisionedPackage -Online |
                    Where-Object { $_.PackageName -like $pattern } |
                    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop }
            } else {
                Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction Stop }
                Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
                Get-AppxProvisionedPackage -Online |
                    Where-Object { $_.PackageName -like $pattern } |
                    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop }
            }
        } catch { }
    }
}

function Clear-StartMenu {
    if (-not (Test-Path $startMenuTemplate)) { return }
    # Replace start2.bin for all existing users
    Get-ChildItem -Path "C:\Users\*\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $target = "$($_.FullName)\start2.bin"
            try {
                if (Test-Path $target) { Move-Item $target "$target.bak" -Force }
                Copy-Item $startMenuTemplate $target -Force
            } catch { }
        }
    # Also apply to Default profile so new users get the layout
    $defaultPath = "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
    try {
        New-Item -Path $defaultPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Copy-Item $startMenuTemplate "$defaultPath\start2.bin" -Force
        Remove-Item $startMenuTemplate -Force
    } catch { }
}

function Apply-SystemTweaks {
    if (-not (Test-Path $regFilesPath)) { return }
    Get-ChildItem -Path $regFilesPath -Filter "*.reg" | ForEach-Object {
        try { reg import $_.FullName | Out-Null } catch { }
    }
}

$appsToRemove = Get-Content -Path $appsListPath -ErrorAction SilentlyContinue |
    ForEach-Object { ($_ -split "#")[0].Trim() } |
    Where-Object { $_ -ne "" }

if ($appsToRemove) { Remove-Apps -AppList $appsToRemove }
Clear-StartMenu
Apply-SystemTweaks
