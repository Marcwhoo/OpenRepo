# DNS Performance Counter Deactivation
# Deactivates DNS performance counters and analytic logs on both DCs

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Performance Counter Deactivation" -ForegroundColor Cyan
Write-Host "<DC-SERVER> and <DC-SERVER>" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

function Disable-DNSPerformanceCounters {
    param([string]$ServerName)
    
    Write-Host "`n=== Deactivating Performance Counters on $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $result = Invoke-Command -Session $session -ScriptBlock {
            $output = @{}
            $dcSetName = "DNS-Performance-Monitoring"
            
            # Check if Data Collector Set exists
            Write-Host "  1. Checking Data Collector Set..." -NoNewline
            try {
                $queryResult = logman query $dcSetName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $output.DataCollectorSetExists = $true
                    $status = logman query $dcSetName | Select-String "Status|Running|Wird ausgefuehrt"
                    $output.DataCollectorSetStatus = if ($status) { "Running" } else { "Stopped" }
                    Write-Host " FOUND (Status: $($output.DataCollectorSetStatus))" -ForegroundColor Green
                }
                else {
                    $output.DataCollectorSetExists = $false
                    Write-Host " NOT FOUND" -ForegroundColor Yellow
                    return $output
                }
            }
            catch {
                $output.DataCollectorSetExists = $false
                Write-Host " NOT FOUND" -ForegroundColor Yellow
                return $output
            }
            
            # Stop Data Collector Set if running
            Write-Host "  2. Stopping Data Collector Set..." -NoNewline
            try {
                if ($output.DataCollectorSetStatus -eq "Running") {
                    logman stop $dcSetName 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $output.DataCollectorSetStopped = $true
                        Write-Host " STOPPED" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    else {
                        $output.DataCollectorSetStopped = $false
                        $output.StopError = "logman stop failed"
                        Write-Host " ERROR" -ForegroundColor Red
                    }
                }
                else {
                    $output.DataCollectorSetStopped = $true
                    Write-Host " WAS NOT STARTED" -ForegroundColor Yellow
                }
            }
            catch {
                $output.DataCollectorSetStopped = $false
                $output.StopError = $_.Exception.Message
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Delete Data Collector Set
            Write-Host "  3. Deleting Data Collector Set..." -NoNewline
            try {
                $maxRetries = 3
                $deleted = $false
                
                for ($i = 1; $i -le $maxRetries; $i++) {
                    logman delete $dcSetName 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $deleted = $true
                        break
                    }
                    else {
                        if ($i -lt $maxRetries) {
                            Write-Host "    Attempt $i/$maxRetries failed, waiting..." -ForegroundColor Yellow
                            Start-Sleep -Seconds 2
                        }
                    }
                }
                
                if ($deleted) {
                    $output.DataCollectorSetDeleted = $true
                    Write-Host " DELETED" -ForegroundColor Green
                }
                else {
                    $output.DataCollectorSetDeleted = $false
                    $output.DeleteError = "Could not delete Data Collector Set after $maxRetries attempts"
                    Write-Host " ERROR" -ForegroundColor Red
                    Write-Host "    Try manually: logman delete $dcSetName" -ForegroundColor Yellow
                }
            }
            catch {
                $output.DataCollectorSetDeleted = $false
                $output.DeleteError = $_.Exception.Message
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Disable DNS Analytic Logs
            Write-Host "  4. Disabling DNS Analytic Logs..." -NoNewline
            try {
                $analyticLog = wevtutil gl "Microsoft-Windows-DNS-Server-Analytic/Operational" 2>&1
                if ($analyticLog -match "enabled:\s*true") {
                    wevtutil sl "Microsoft-Windows-DNS-Server-Analytic/Operational" /e:false 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $output.AnalyticLogDisabled = $true
                        Write-Host " DISABLED" -ForegroundColor Green
                    }
                    else {
                        $output.AnalyticLogDisabled = $false
                        Write-Host " ERROR" -ForegroundColor Red
                    }
                }
                else {
                    $output.AnalyticLogDisabled = $true
                    Write-Host " WAS NOT ENABLED" -ForegroundColor Yellow
                }
            }
            catch {
                $output.AnalyticLogDisabled = $false
                $output.AnalyticLogError = $_.Exception.Message
                Write-Host " ERROR" -ForegroundColor Red
            }
            
            # Remove Scheduled Task for Analytic Log Export
            Write-Host "  5. Removing Scheduled Task for Analytic Log Export..." -NoNewline
            try {
                $taskName = "DNS-Analytic-Log-Export"
                $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($existingTask) {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                    $output.ScheduledTaskRemoved = $true
                    Write-Host " REMOVED" -ForegroundColor Green
                }
                else {
                    $output.ScheduledTaskRemoved = $true
                    Write-Host " NOT FOUND" -ForegroundColor Yellow
                }
            }
            catch {
                $output.ScheduledTaskRemoved = $false
                $output.ScheduledTaskError = $_.Exception.Message
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Check log files
            Write-Host "  6. Checking log files..." -NoNewline
            $logPath = "C:\PerfLogs\DNS-Performance"
            if (Test-Path $logPath) {
                $logFiles = Get-ChildItem -Path $logPath -ErrorAction SilentlyContinue
                $output.LogPath = $logPath
                $output.LogFilesCount = $logFiles.Count
                $output.LogFilesSizeMB = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                Write-Host " FOUND ($($logFiles.Count) files, $($output.LogFilesSizeMB) MB)" -ForegroundColor Yellow
                Write-Host "    Log files are NOT automatically deleted." -ForegroundColor Yellow
                Write-Host "    To delete: Remove-Item '$logPath\*' -Recurse -Force" -ForegroundColor Cyan
                $output.LogsDeleted = $false
            }
            else {
                Write-Host " NOT FOUND" -ForegroundColor Green
                $output.LogPath = $logPath
                $output.LogFilesCount = 0
            }
            
            return $output
        }
        
        Remove-PSSession $session
        return $result
    }
    catch {
        Write-Warning "Error on $ServerName : $($_.Exception.Message)"
        return @{ Error = $_.Exception.Message }
    }
}

Write-Host "`nWARNING: This will deactivate DNS Performance Counter monitoring!" -ForegroundColor Yellow
Write-Host "Continuing with deactivation..." -ForegroundColor Cyan

Write-Host "`nDeactivating DNS Performance Counters..." -ForegroundColor Cyan

$dc01Result = Disable-DNSPerformanceCounters -ServerName "<DC-SERVER>"
$dc02Result = Disable-DNSPerformanceCounters -ServerName "<DC-SERVER>"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc01Result.DataCollectorSetExists) {
    if ($dc01Result.DataCollectorSetStopped) { Write-Host "  [OK] Data Collector Set stopped" -ForegroundColor Green }
    if ($dc01Result.DataCollectorSetDeleted) { Write-Host "  [OK] Data Collector Set deleted" -ForegroundColor Green }
    if ($dc01Result.AnalyticLogDisabled) { Write-Host "  [OK] DNS Analytic Logs disabled" -ForegroundColor Green }
    if ($dc01Result.ScheduledTaskRemoved) { Write-Host "  [OK] Scheduled Task removed" -ForegroundColor Green }
    if ($dc01Result.LogFilesCount -gt 0) {
        $sizeMB = $dc01Result.LogFilesSizeMB
        Write-Host "  Log files: $($dc01Result.LogFilesCount) files ($sizeMB MB)" -ForegroundColor Yellow
        Write-Host "     Path: $($dc01Result.LogPath)" -ForegroundColor Cyan
    }
}
else {
    Write-Host "  [WARN] Data Collector Set was not found" -ForegroundColor Yellow
}

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc02Result.DataCollectorSetExists) {
    if ($dc02Result.DataCollectorSetStopped) { Write-Host "  [OK] Data Collector Set stopped" -ForegroundColor Green }
    if ($dc02Result.DataCollectorSetDeleted) { Write-Host "  [OK] Data Collector Set deleted" -ForegroundColor Green }
    if ($dc02Result.AnalyticLogDisabled) { Write-Host "  [OK] DNS Analytic Logs disabled" -ForegroundColor Green }
    if ($dc02Result.ScheduledTaskRemoved) { Write-Host "  [OK] Scheduled Task removed" -ForegroundColor Green }
    if ($dc02Result.LogFilesCount -gt 0) {
        $sizeMB = $dc02Result.LogFilesSizeMB
        Write-Host "  Log files: $($dc02Result.LogFilesCount) files ($sizeMB MB)" -ForegroundColor Yellow
        Write-Host "     Path: $($dc02Result.LogPath)" -ForegroundColor Cyan
    }
}
else {
    Write-Host "  [WARN] Data Collector Set was not found" -ForegroundColor Yellow
}

$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DC01 = $dc01Result
    DC02 = $dc02Result
}

$jsonPath = ".\DNS-Performance-Counter-Deaktivierung-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Results saved ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

Write-Host "`n[OK] Deactivation completed!" -ForegroundColor Green
Write-Host "`nNote: Log files were NOT deleted." -ForegroundColor Yellow
Write-Host "To delete log files on each server:" -ForegroundColor Cyan
Write-Host "  Remove-Item 'C:\PerfLogs\DNS-Performance\*' -Recurse -Force" -ForegroundColor White

$results
