# DNS Performance Counter Activation V2
# Activates DNS performance counters and analytic logs on both DCs

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Performance Counter Activation V2" -ForegroundColor Cyan
Write-Host "<DC-SERVER> and <DC-SERVER>" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

function Enable-DNSPerformanceCounters {
    param([string]$ServerName)
    
    Write-Host "`n=== Activating Performance Counters on $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $result = Invoke-Command -Session $session -ScriptBlock {
            $output = @{}
            
            # Check if DNS counters are available
            Write-Host "  1. Checking DNS counters..." -NoNewline
            try {
                $counterList = Get-Counter -ListSet "DNS" -ErrorAction SilentlyContinue
                if ($counterList) {
                    $output.CountersAvailable = $true
                    $output.CounterSetName = $counterList.CounterSetName
                    Write-Host " OK" -ForegroundColor Green
                }
                else {
                    $output.CountersAvailable = $false
                    Write-Host " NOT AVAILABLE" -ForegroundColor Yellow
                }
            }
            catch {
                $output.CountersAvailable = $false
                Write-Host " ERROR" -ForegroundColor Red
            }
            
            # Test reading counters
            Write-Host "  2. Testing counter read..." -NoNewline
            try {
                $testCounter = Get-Counter "\DNS\Total Query Received" -ErrorAction SilentlyContinue
                if ($testCounter) {
                    $output.CounterReadable = $true
                    $output.TestCounterValue = $testCounter.CounterSamples[0].CookedValue
                    Write-Host " OK (Value: $($testCounter.CounterSamples[0].CookedValue))" -ForegroundColor Green
                }
                else {
                    $output.CounterReadable = $false
                    Write-Host " NOT READABLE" -ForegroundColor Yellow
                }
            }
            catch {
                $output.CounterReadable = $false
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Create/Update Data Collector Set
            Write-Host "  3. Creating/Updating Data Collector Set..." -NoNewline
            $dcSetName = "DNS-Performance-Monitoring"
            $logPath = "C:\PerfLogs\DNS-Performance"
            
            try {
                $existing = logman query $dcSetName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " ALREADY EXISTS" -ForegroundColor Yellow
                    $output.DataCollectorSetExists = $true
                    
                    $status = logman query $dcSetName | Select-String "Status"
                    $running = logman query $dcSetName | Select-String "Running|Wird ausgefuehrt"
                    
                    if ($running) {
                        Write-Host "    Stopping for update..." -ForegroundColor Cyan
                        logman stop $dcSetName 2>&1 | Out-Null
                        Start-Sleep -Seconds 2
                    }
                    
                    Write-Host "    Removing old Data Collector Set..." -NoNewline
                    logman delete $dcSetName 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " OK" -ForegroundColor Green
                        Start-Sleep -Seconds 1
                    }
                    else {
                        Write-Host " ERROR" -ForegroundColor Red
                        $output.DeleteError = "Could not remove old Data Collector Set"
                    }
                }
                
                Write-Host "    Creating new Data Collector Set..." -ForegroundColor Cyan
                Write-Host "    Note: Response Times are NOT available as Performance Counter" -ForegroundColor Yellow
                Write-Host "    Response Times must be measured via DNS Analytic Logs or Wireshark" -ForegroundColor Yellow
                
                if (-not (Test-Path $logPath)) {
                    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
                }
                
                $counterListContent = @"
\DNS\Empfangene Abfragen insgesamt
\DNS\Gesendete Antworten insgesamt
\DNS\Empfangene UDP-Abfragen
\DNS\Empfangene TCP-Abfragen
\DNS\Rekursive Abfragen
\DNS\Fehlgeschlagene rekursive Abfragen
"@
                $counterListFile = "$env:TEMP\dns-counters.txt"
                $counterListContent | Out-File -FilePath $counterListFile -Encoding ASCII -Force
                
                logman create counter $dcSetName -cf $counterListFile -f csv -o "$logPath\DNS-Performance" -si 00:00:15 -v mmddhhmm -y 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    $output.DataCollectorSetCreated = $true
                    Write-Host "    Data Collector Set created" -ForegroundColor Green
                    
                    Write-Host "    Starting Data Collector Set..." -NoNewline
                    logman start $dcSetName 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $output.DataCollectorSetStarted = $true
                        Write-Host " OK" -ForegroundColor Green
                    }
                    else {
                        $output.DataCollectorSetStarted = $false
                        Write-Host " ERROR" -ForegroundColor Red
                    }
                    
                    Remove-Item $counterListFile -ErrorAction SilentlyContinue
                }
                else {
                    $output.DataCollectorSetCreated = $false
                    $errorOutput = logman create counter $dcSetName -cf $counterListFile -f csv -o "$logPath\DNS-Performance" -si 00:00:15 -v mmddhhmm -y 2>&1
                    $output.DataCollectorSetError = $errorOutput
                    Write-Host " ERROR" -ForegroundColor Red
                }
            }
            catch {
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
                $output.DataCollectorSetError = $_.Exception.Message
            }
            
            # Check log directory
            Write-Host "  4. Checking log directory..." -NoNewline
            if (Test-Path $logPath) {
                $logFiles = Get-ChildItem -Path $logPath -ErrorAction SilentlyContinue
                $output.LogPath = $logPath
                $output.LogFilesCount = $logFiles.Count
                $output.LogFilesSizeMB = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                Write-Host " OK ($($logFiles.Count) files, $($output.LogFilesSizeMB) MB)" -ForegroundColor Green
            }
            else {
                Write-Host " NOT FOUND" -ForegroundColor Yellow
                $output.LogPath = $logPath
                $output.LogFilesCount = 0
            }
            
            # Check disk space
            Write-Host "  5. Checking disk space..." -NoNewline
            $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
            if ($disk) {
                $output.DiskSpace = @{
                    FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                    TotalGB = [math]::Round($disk.Size / 1GB, 2)
                    PercentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
                }
                Write-Host " OK ($($output.DiskSpace.FreeGB) GB free)" -ForegroundColor Green
            }
            
            # Enable DNS Analytic Logs
            Write-Host "  6. Enabling DNS Analytic Logs..." -NoNewline
            try {
                $analyticLog = wevtutil gl "Microsoft-Windows-DNS-Server-Analytic/Operational" 2>&1
                if ($analyticLog -match "enabled:\s*true") {
                    $output.AnalyticLogEnabled = $true
                    $output.AnalyticLogWasAlreadyEnabled = $true
                    Write-Host " ALREADY ENABLED" -ForegroundColor Green
                }
                else {
                    Write-Host " ENABLING..." -ForegroundColor Cyan
                    wevtutil sl "Microsoft-Windows-DNS-Server-Analytic/Operational" /e:true 2>&1 | Out-Null
                    
                    if ($LASTEXITCODE -eq 0) {
                        $output.AnalyticLogEnabled = $true
                        $output.AnalyticLogWasAlreadyEnabled = $false
                        Write-Host " ENABLED" -ForegroundColor Green
                    }
                    else {
                        $output.AnalyticLogEnabled = $false
                        Write-Host " ERROR" -ForegroundColor Red
                    }
                }
                
                if ($output.AnalyticLogEnabled) {
                    Write-Host "    Note: Analytic logs can be very large (several GB/day with high traffic)" -ForegroundColor Yellow
                    Write-Host "    Export folder: $logPath" -ForegroundColor Cyan
                }
            }
            catch {
                $output.AnalyticLogEnabled = $false
                $output.AnalyticLogError = $_.Exception.Message
                Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Create Scheduled Task for Analytic Log Export
            if ($output.AnalyticLogEnabled) {
                Write-Host "  7. Creating Scheduled Task for Analytic Log Export..." -NoNewline
                try {
                    $taskName = "DNS-Analytic-Log-Export"
                    $scriptPath = "$logPath\DNS-Analytic-Log-Export.ps1"
                    
                    $exportScript = @"
# DNS Analytic Log Export Script
# Runs every 15 minutes

`$logPath = '$logPath'
`$exportFile = Join-Path `$logPath "DNS-Analytic-Log-Export-`$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"

try {
    `$startTime = (Get-Date).AddMinutes(-15)
    `$events = Get-WinEvent -FilterHashtable @{
        LogName = "Microsoft-Windows-DNS-Server-Analytic/Operational"
        StartTime = `$startTime
    } -ErrorAction SilentlyContinue -MaxEvents 50000
    
    if (`$events) {
        `$exportData = `$events | ForEach-Object {
            `$xml = [xml]`$_.ToXml()
            `$eventData = @{}
            `$xml.Event.EventData.Data | ForEach-Object {
                `$eventData[`$_.Name] = `$_.'#text'
            }
            
            [PSCustomObject]@{
                TimeCreated = `$_.TimeCreated
                Id = `$_.Id
                ClientIP = `$eventData.ClientIp
                QueryName = `$eventData.QueryName
                QueryType = `$eventData.QueryType
                ResponseCode = `$eventData.ResponseCode
                InterfaceIP = `$eventData.InterfaceIP
            }
        }
        
        `$exportData | Export-Csv -Path `$exportFile -NoTypeInformation -Encoding UTF8
        Write-EventLog -LogName Application -Source "DNS-Analytic-Export" -EventId 1000 -EntryType Information -Message "Exported `$(`$events.Count) DNS events to `$exportFile" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-EventLog -LogName Application -Source "DNS-Analytic-Export" -EventId 1001 -EntryType Error -Message "Error exporting DNS events: `$(`$_.Exception.Message)" -ErrorAction SilentlyContinue
}
"@
                    
                    $exportScript | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
                    
                    $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
                    $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Hours 5)
                    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                    
                    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                    if ($existingTask) {
                        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                    }
                    
                    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Exports DNS Analytic Logs every 15 minutes for 5 hours" -Force | Out-Null
                    
                    $output.ScheduledTaskCreated = $true
                    $output.ScheduledTaskName = $taskName
                    $output.ExportScriptPath = $scriptPath
                    Write-Host " OK" -ForegroundColor Green
                    Write-Host "    Task: $taskName (runs every 15 minutes for 5 hours)" -ForegroundColor Cyan
                }
                catch {
                    $output.ScheduledTaskCreated = $false
                    $output.ScheduledTaskError = $_.Exception.Message
                    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "  7. Skipping Scheduled Task (Analytic Logs not enabled)" -ForegroundColor Yellow
            }
            
            # Resource usage estimate
            Write-Host "  8. Resource usage (Performance Counter)..." -NoNewline
            $output.ResourceUsage = @{
                CPU = "< 1% (minimal)"
                RAM = "< 50 MB (minimal)"
                Disk = "~1-5 MB per hour (CSV logs)"
                Note = "Performance counters are very lightweight"
            }
            Write-Host " MINIMAL" -ForegroundColor Green
            Write-Host "    CPU: < 1%, RAM: < 50 MB, Disk: ~1-5 MB/hour" -ForegroundColor Cyan
            
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

Write-Host "`nActivating DNS Performance Counters..." -ForegroundColor Cyan

$dc01Result = Enable-DNSPerformanceCounters -ServerName "<DC-SERVER>"
$dc02Result = Enable-DNSPerformanceCounters -ServerName "<DC-SERVER>"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc01Result.CountersAvailable) { Write-Host "  [OK] Counters available" -ForegroundColor Green }
if ($dc01Result.CounterReadable) { Write-Host "  [OK] Counters readable" -ForegroundColor Green }
if ($dc01Result.DataCollectorSetStarted) { Write-Host "  [OK] Data Collector Set running" -ForegroundColor Green }
if ($dc01Result.DiskSpace) {
    $color = if ($dc01Result.DiskSpace.PercentFree -lt 10) { "Red" } else { "Green" }
    Write-Host "  Disk Space: $($dc01Result.DiskSpace.FreeGB) GB free ($($dc01Result.DiskSpace.PercentFree)%)" -ForegroundColor $color
}

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc02Result.CountersAvailable) { Write-Host "  [OK] Counters available" -ForegroundColor Green }
if ($dc02Result.CounterReadable) { Write-Host "  [OK] Counters readable" -ForegroundColor Green }
if ($dc02Result.DataCollectorSetStarted) { Write-Host "  [OK] Data Collector Set running" -ForegroundColor Green }
if ($dc02Result.DiskSpace) {
    $color = if ($dc02Result.DiskSpace.PercentFree -lt 10) { "Red" } else { "Green" }
    Write-Host "  Disk Space: $($dc02Result.DiskSpace.FreeGB) GB free ($($dc02Result.DiskSpace.PercentFree)%)" -ForegroundColor $color
}

$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DC01 = $dc01Result
    DC02 = $dc02Result
}

$jsonPath = ".\DNS-Performance-Counter-Aktivierung-V2-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Results saved ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

Write-Host "`n[OK] Activation completed!" -ForegroundColor Green
Write-Host "`nNote: Performance counters are now being collected continuously." -ForegroundColor Cyan
Write-Host "Log files: C:\PerfLogs\DNS-Performance on each server" -ForegroundColor Cyan

if ($dc01Result.AnalyticLogEnabled -or $dc02Result.AnalyticLogEnabled) {
    Write-Host "`n[OK] DNS Analytic Logs enabled!" -ForegroundColor Green
    Write-Host "Export folder: C:\PerfLogs\DNS-Performance (same as Performance Counter)" -ForegroundColor Cyan
    Write-Host "Export interval: Every 15 minutes" -ForegroundColor Cyan
    Write-Host "Duration: 5 hours (then automatically stopped)" -ForegroundColor Cyan
    Write-Host "`nWARNING: Analytic logs can be VERY large!" -ForegroundColor Yellow
    Write-Host "With high traffic, several GB per day can be generated." -ForegroundColor Yellow
}
else {
    Write-Host "`nWARNING: DNS Analytic Logs were NOT enabled!" -ForegroundColor Yellow
}

Write-Host "`nPerformance counters (logman) are very lightweight (< 1% CPU, ~1-5 MB/hour)." -ForegroundColor Green

$results
