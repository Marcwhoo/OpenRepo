# DNS Wireshark Trace on Remote Server
# Captures DNS traffic - ONLY captures, session stays open

param(
    [string]$ServerName = "<DC-SERVER>",
    [int]$DurationMinutes = 60,
    [string]$RemotePath = "C:\PerfLogs\DNS-Performance"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Wireshark Trace (Remote)" -ForegroundColor Cyan
Write-Host "Server: $ServerName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# Check if tshark exists on remote server
Write-Host "`nChecking for tshark on remote server..." -NoNewline
try {
    $tsharkCheck = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        $tsharkPath = "C:\Program Files\Wireshark\tshark.exe"
        if (Test-Path $tsharkPath) {
            return $tsharkPath
        }
        return $null
    }
    
    if ($tsharkCheck) {
        Write-Host " FOUND" -ForegroundColor Green
        $tsharkPath = $tsharkCheck
    }
    else {
        Write-Host " NOT FOUND" -ForegroundColor Red
        Write-Host "ERROR: Wireshark/tshark not installed on $ServerName" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Ensure remote directory exists
Write-Host "Ensuring remote directory exists..." -NoNewline
try {
    Invoke-Command -ComputerName $ServerName -ScriptBlock {
        param($path)
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    } -ArgumentList $RemotePath | Out-Null
    Write-Host " OK" -ForegroundColor Green
}
catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$remoteFile = Join-Path $RemotePath "DNS-Trace-$timestamp.pcapng"
$durationSeconds = $DurationMinutes * 60

Write-Host "`nStarting DNS capture on $ServerName..." -ForegroundColor Cyan
Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Yellow
Write-Host "Remote file: $remoteFile" -ForegroundColor Yellow
Write-Host ""

# Create persistent session
Write-Host "Creating persistent session..." -NoNewline
try {
    $session = New-PSSession -ComputerName $ServerName
    Write-Host " OK" -ForegroundColor Green
}
catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Start capture on remote server
try {
    Write-Host "Starting capture process..." -ForegroundColor Cyan
    
    # Get interface number first
    Write-Host "Detecting network interface..." -NoNewline
    $interfaceInfo = Invoke-Command -Session $session -ScriptBlock {
        param($tshark)
        $interfaces = & $tshark -D 2>&1
        $ethernetInterface = $interfaces | Where-Object { $_ -match 'Ethernet' -and $_ -notmatch 'Loopback' } | Select-Object -First 1
        $interfaceNum = "0"
        if ($ethernetInterface) {
            $interfaceNum = ($ethernetInterface -split '\.')[0].Trim()
        }
        return $interfaceNum
    } -ArgumentList $tsharkPath
    Write-Host " OK (Interface: $interfaceInfo)" -ForegroundColor Green
    
    # Start capture in background job within session
    Write-Host "Starting capture process..." -NoNewline
    $job = Invoke-Command -Session $session -ScriptBlock {
        param($tshark, $output, $duration, $filter, $interfaceNum)
        
        $argsString = "-i $interfaceNum -f `"$filter`" -w `"$output`" -a duration:$duration"
        
        # Start process in background
        $process = Start-Process -FilePath $tshark -ArgumentList $argsString -PassThru -WindowStyle Hidden
        
        if (-not $process) {
            return @{
                Id = $null
                Interface = $interfaceNum
                Success = $false
                ErrorMessage = "Failed to start process"
            }
        }
        
        # Wait a moment to verify process started
        Start-Sleep -Seconds 5
        
        # Check if still running
        $process.Refresh()
        if (-not $process.HasExited) {
            return @{
                Id = $process.Id
                Interface = $interfaceNum
                Success = $true
            }
        }
        else {
            return @{
                Id = $null
                Interface = $interfaceNum
                Success = $false
                ErrorMessage = "Process exited immediately with code: $($process.ExitCode)"
            }
        }
    } -ArgumentList $tsharkPath, $remoteFile, $durationSeconds, "port 53", $interfaceInfo -AsJob
    
    # Get result from job
    $captureResult = Receive-Job -Job $job -Wait
    
    if (-not $captureResult.Success) {
        Write-Host " ERROR: Capture failed to start!" -ForegroundColor Red
        Write-Host "Error: $($captureResult.ErrorMessage)" -ForegroundColor Red
        Remove-PSSession $session
        exit 1
    }
    
    Write-Host " OK" -ForegroundColor Green
    Write-Host "Capture started successfully!" -ForegroundColor Green
    Write-Host "Process ID: $($captureResult.Id)" -ForegroundColor Cyan
    Write-Host "Interface: $($captureResult.Interface)" -ForegroundColor Cyan
    Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Cyan
    Write-Host "Output file: $remoteFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Capture is running!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "WICHTIG: Diese PowerShell-Session muss OFFEN bleiben!" -ForegroundColor Red
    Write-Host "Wenn Sie dieses Fenster schliessen, wird der Capture-Prozess beendet!" -ForegroundColor Red
    Write-Host ""
    Write-Host "The capture will run for $DurationMinutes minutes." -ForegroundColor Yellow
    Write-Host "After completion, manually:" -ForegroundColor Yellow
    Write-Host "  1. Copy file from: \\$ServerName\C$\PerfLogs\DNS-Performance\DNS-Trace-$timestamp.pcapng" -ForegroundColor White
    Write-Host "  2. Delete file from server after copying" -ForegroundColor White
    Write-Host "  3. Run analysis script: .\DNS-Wireshark-Analyse.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "To check if capture is still running:" -ForegroundColor Cyan
    Write-Host "  Get-Process -Id $($captureResult.Id) -ComputerName $ServerName" -ForegroundColor White
    Write-Host ""
    Write-Host "To check file size:" -ForegroundColor Cyan
    Write-Host "  Get-Item \\$ServerName\C$\PerfLogs\DNS-Performance\DNS-Trace-$timestamp.pcapng" -ForegroundColor White
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Session is open - DO NOT CLOSE THIS WINDOW!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Keep session alive by waiting for process to complete
    $waitTime = ($DurationMinutes * 60) + 60
    Write-Host "Waiting for capture to complete ($DurationMinutes minutes)..." -ForegroundColor Cyan
    Write-Host "This window will stay open. Press Ctrl+C to stop early." -ForegroundColor Yellow
    Write-Host ""
    
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($waitTime)
    
    while ((Get-Date) -lt $endTime) {
        $remaining = ($endTime - (Get-Date)).TotalMinutes
        $processRunning = Invoke-Command -Session $session -ScriptBlock {
            param($processId)
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            return ($null -ne $proc)
        } -ArgumentList $captureResult.Id
        
        if (-not $processRunning) {
            Write-Host "Capture process has completed!" -ForegroundColor Green
            break
        }
        
        Write-Host "Capture running... $([math]::Round($remaining, 1)) minutes remaining (Process ID: $($captureResult.Id))" -ForegroundColor Cyan
        Start-Sleep -Seconds 60
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Capture session ended!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now close this window." -ForegroundColor Yellow
    
    # Clean up
    Remove-PSSession $session
}
catch {
    Write-Host "[ERROR] Capture failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($session) {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
    exit 1
}
