#Requires -RunAsAdministrator
# Windows disk cleanup: temp files, recycle bin, cleanmgr, WU download cache, event logs.
# Logs freed space before and after to C:\EDV\upgradelogs\cleanup.log

$logPath = "C:\EDV\upgradelogs\cleanup.log"
$logDir  = "C:\EDV\upgradelogs"

function Write-Log {
    param ($Message)
    "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) - $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

Write-Host "Starting disk cleanup..."
Write-Log "Cleanup started"

$freeSpaceBefore = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)
Write-Log "Free space before: $freeSpaceBefore GB"

try {
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction Stop
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction Stop
    Write-Log "Temp files deleted"
} catch {
    Write-Log "Error deleting temp files: $_"
}

try {
    Clear-RecycleBin -Force -ErrorAction Stop
    Write-Log "Recycle bin emptied"
} catch {
    Write-Log "Error emptying recycle bin: $_"
}

# Enable all cleanmgr categories via StateFlags0001 and run silently
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    Get-ChildItem -Path $regPath | Select-Object -ExpandProperty Name | ForEach-Object {
        Set-ItemProperty -Path $_ -Name "StateFlags0001" -Value 2 -ErrorAction Stop
    }
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -NoNewWindow -ErrorAction Stop
    Write-Log "cleanmgr completed"
} catch {
    Write-Log "Error running cleanmgr: $_"
}

try {
    Stop-Service -Name wuauserv -Force -ErrorAction Stop
    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction Stop
    Start-Service -Name wuauserv -ErrorAction Stop
    Write-Log "Windows Update download cache cleared"
} catch {
    Write-Log "Error clearing WU cache: $_"
}

try {
    Get-EventLog -LogName * | ForEach-Object { Clear-EventLog -LogName $_.Log -ErrorAction Stop }
    Write-Log "Event logs cleared"
} catch {
    Write-Log "Error clearing event logs: $_"
}

$freeSpaceAfter  = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)
$freedSpace      = [math]::Round($freeSpaceAfter - $freeSpaceBefore, 2)

Write-Host "Done. Freed: $freedSpace GB"
Write-Log "Free space after: $freeSpaceAfter GB | Freed: $freedSpace GB"
