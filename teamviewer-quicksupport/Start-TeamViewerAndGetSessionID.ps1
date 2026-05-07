# Starts TeamViewer QuickSupport, extracts the latest session ID and password from the log,
# and saves the result to a text file.
# For central collection: change $outputFile to a network share path like "\\Server\Share\$env:COMPUTERNAME.txt"

param (
    [string]$teamViewerPath = "C:\EDV\TeamViewerQS.exe",
    [string]$logPath        = "$env:LOCALAPPDATA\TeamViewer\Logs\TeamViewer15_Logfile.log",
    [string]$outputFile     = "C:\EDV\TeamViewerID.txt"
)

Get-Process -Name "TeamViewer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $teamViewerPath) {
    Start-Process -FilePath $teamViewerPath -NoNewWindow
    Start-Sleep -Seconds 15  # Wait for session ID to appear in log
} else {
    "Error: TeamViewerQS.exe not found at $teamViewerPath." | Out-File -FilePath $outputFile -Force
    exit
}

if (-not (Test-Path $logPath)) {
    "Error: Log file not found at $logPath." | Out-File -FilePath $outputFile -Force
    exit
}

$logContent = Get-Content -Path $logPath -Raw

$idMatches = [regex]::Matches($logContent, "(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{3}).*?InstantSupport-Session (s\d{3}-\d{3}-\d{3})")

if ($idMatches.Count -gt 0) {
    $idList = @()
    foreach ($match in $idMatches) {
        try {
            $timestamp = [datetime]::ParseExact($match.Groups[1].Value, "yyyy/MM/dd HH:mm:ss.fff", $null)
            $idList += [PSCustomObject]@{ Timestamp = $timestamp; SessionID = $match.Groups[2].Value }
        } catch { }
    }

    $latestID = ($idList | Sort-Object Timestamp -Descending | Select-Object -First 1).SessionID

    $pwMatch  = [regex]::Match($logContent, "Password: (\w+)")
    $password = if ($pwMatch.Success) { $pwMatch.Groups[1].Value } else { "Not available" }

    "TeamViewer-ID: $latestID" | Out-File -FilePath $outputFile -Force
    "Password: $password"      | Out-File -FilePath $outputFile -Append
    Write-Host "Saved: ID $latestID / Password $password -> $outputFile"
} else {
    "Error: No session ID found in log." | Out-File -FilePath $outputFile -Force
    Write-Host "Error: No session ID found."
}
