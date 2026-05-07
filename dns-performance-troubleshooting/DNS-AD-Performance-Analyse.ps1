# DNS and AD Database Performance Analysis
# Checks AD database performance and DNS service performance

param(
    [string]$DcName = "<DC-SERVER>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS and AD Database Performance Analysis" -ForegroundColor Cyan
Write-Host "Domain Controller: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. AD Database Information
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. AD DATABASE INFORMATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $adDbInfo = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $ntdsPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters")."DSA Database file"
        $dbPath = $ntdsPath -replace "\\\\.*", ""
        $dbFile = Get-Item $dbPath -ErrorAction SilentlyContinue
        
        if ($dbFile) {
            return @{
                DatabasePath = $dbPath
                DatabaseSizeMB = [math]::Round($dbFile.Length / 1MB, 2)
                LastModified = $dbFile.LastWriteTime
                Age = ((Get-Date) - $dbFile.LastWriteTime).Days
            }
        }
        return $null
    }
    
    if ($adDbInfo) {
        Write-Host "AD Database Path: $($adDbInfo.DatabasePath)" -ForegroundColor White
        Write-Host "Database Size: $($adDbInfo.DatabaseSizeMB) MB" -ForegroundColor White
        Write-Host "Last Modified: $($adDbInfo.LastModified)" -ForegroundColor White
        Write-Host "Age: $($adDbInfo.Age) days" -ForegroundColor White
    }
    else {
        Write-Host "Could not retrieve AD database information" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not check AD database: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 2. AD Database Performance Counters
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. AD DATABASE PERFORMANCE COUNTERS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $adPerfCounters = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $counters = @(
            "\NTDS\Database\File Size",
            "\NTDS\Database\Cache Hit Rate",
            "\NTDS\Database\Cache Size",
            "\NTDS\Database\Page Faults/sec",
            "\NTDS\Database\Page Reads/sec",
            "\NTDS\Database\Page Writes/sec",
            "\NTDS\Database\LS Add/sec",
            "\NTDS\Database\LS Delete/sec",
            "\NTDS\Database\LS Search/sec"
        )
        
        $results = @()
        foreach ($counter in $counters) {
            try {
                $value = (Get-Counter -Counter $counter -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
                $results += [PSCustomObject]@{
                    Counter = $counter
                    Value = if ($value) { [math]::Round($value, 2) } else { "N/A" }
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    Counter = $counter
                    Value = "N/A"
                }
            }
        }
        return $results
    }
    
    Write-Host "AD Database Performance Counters:" -ForegroundColor Yellow
    $adPerfCounters | Format-Table -AutoSize
}
catch {
    Write-Host "ERROR: Could not check AD performance counters: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 3. DNS Service Performance
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. DNS SERVICE PERFORMANCE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $dnsPerf = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $dnsProcess = Get-Process -Name "dns" -ErrorAction SilentlyContinue
        
        if ($dnsProcess) {
            $cpu = Get-Counter "\Process(dns)\% Processor Time" -ErrorAction SilentlyContinue
            $mem = Get-Counter "\Process(dns)\Working Set - Private" -ErrorAction SilentlyContinue
            
            return [PSCustomObject]@{
                ProcessId = $dnsProcess.Id
                CPUPercent = if ($cpu) { [math]::Round($cpu.CounterSamples[0].CookedValue, 2) } else { "N/A" }
                MemoryMB = if ($mem) { [math]::Round($mem.CounterSamples[0].CookedValue / 1MB, 2) } else { [math]::Round($dnsProcess.WorkingSet64 / 1MB, 2) }
                Threads = $dnsProcess.Threads.Count
                Handles = $dnsProcess.HandleCount
            }
        }
        return $null
    }
    
    if ($dnsPerf) {
        Write-Host "DNS Service Performance:" -ForegroundColor Yellow
        $dnsPerf | Format-List
    }
    else {
        Write-Host "DNS process not found" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not check DNS service performance: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 4. System Resources
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. SYSTEM RESOURCES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $systemResources = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $mem = Get-Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue
        $memTotal = Get-Counter "\Memory\Total MBytes" -ErrorAction SilentlyContinue
        $disk = Get-Counter "\LogicalDisk(C:)\% Disk Time" -ErrorAction SilentlyContinue
        
        return [PSCustomObject]@{
            CPUPercent = if ($cpu) { [math]::Round($cpu.CounterSamples[0].CookedValue, 2) } else { "N/A" }
            AvailableMemoryMB = if ($mem) { [math]::Round($mem.CounterSamples[0].CookedValue, 0) } else { "N/A" }
            TotalMemoryMB = if ($memTotal) { [math]::Round($memTotal.CounterSamples[0].CookedValue, 0) } else { "N/A" }
            MemoryUsagePercent = if ($memTotal -and $mem) { [math]::Round((($memTotal.CounterSamples[0].CookedValue - $mem.CounterSamples[0].CookedValue) / $memTotal.CounterSamples[0].CookedValue) * 100, 2) } else { "N/A" }
            DiskTimePercent = if ($disk) { [math]::Round($disk.CounterSamples[0].CookedValue, 2) } else { "N/A" }
        }
    }
    
    Write-Host "System Resources:" -ForegroundColor Yellow
    $systemResources | Format-List
    
    # Check if resources are constrained
    $warnings = @()
    if ($systemResources.CPUPercent -ne "N/A" -and $systemResources.CPUPercent -gt 80) {
        $warnings += "CPU usage is high: $($systemResources.CPUPercent)%"
    }
    if ($systemResources.MemoryUsagePercent -ne "N/A" -and $systemResources.MemoryUsagePercent -gt 90) {
        $warnings += "Memory usage is high: $($systemResources.MemoryUsagePercent)%"
    }
    if ($systemResources.DiskTimePercent -ne "N/A" -and $systemResources.DiskTimePercent -gt 80) {
        $warnings += "Disk usage is high: $($systemResources.DiskTimePercent)%"
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "WARNINGS:" -ForegroundColor Red
        foreach ($warning in $warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "ERROR: Could not check system resources: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. Network Latency Test
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. NETWORK LATENCY TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    Write-Host "Testing network latency to $DcName..." -ForegroundColor Yellow
    
    $pingResults = Test-Connection -ComputerName $DcName -Count 10 -ErrorAction SilentlyContinue
    if ($pingResults) {
        $avgLatency = ($pingResults | Measure-Object -Property ResponseTime -Average).Average
        $minLatency = ($pingResults | Measure-Object -Property ResponseTime -Minimum).Minimum
        $maxLatency = ($pingResults | Measure-Object -Property ResponseTime -Maximum).Maximum
        $packetLoss = (10 - $pingResults.Count) * 10
        
        Write-Host "Average Latency: $([math]::Round($avgLatency, 2)) ms" -ForegroundColor White
        Write-Host "Min Latency: $([math]::Round($minLatency, 2)) ms" -ForegroundColor White
        Write-Host "Max Latency: $([math]::Round($maxLatency, 2)) ms" -ForegroundColor White
        Write-Host "Packet Loss: $packetLoss%" -ForegroundColor $(if ($packetLoss -gt 0) { "Red" } else { "Green" })
        
        if ($avgLatency -gt 10) {
            Write-Host "WARNING: Network latency is high!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Could not test network latency" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not test network latency: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 6. DNS Query Performance Test (Direct vs Remote)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. DNS QUERY PERFORMANCE TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $testDomain = "<DOMAIN-FQDN>"
    
    Write-Host "Testing DNS resolution performance..." -ForegroundColor Yellow
    Write-Host ""
    
    # Test from local machine
    Write-Host "From local machine to ${DcName}:" -ForegroundColor Yellow
    $localTimes = @()
    for ($i = 1; $i -le 10; $i++) {
        $startTime = Get-Date
        $result = Resolve-DnsName -Name $testDomain -Server $DcName -ErrorAction SilentlyContinue
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        $localTimes += $duration
    }
    $localAvg = ($localTimes | Measure-Object -Average).Average
    $localMin = ($localTimes | Measure-Object -Minimum).Minimum
    $localMax = ($localTimes | Measure-Object -Maximum).Maximum
    
    Write-Host "  Avg: $([math]::Round($localAvg, 2))ms, Min: $([math]::Round($localMin, 2))ms, Max: $([math]::Round($localMax, 2))ms" -ForegroundColor $(if ($localAvg -gt 100) { "Red" } elseif ($localAvg -gt 50) { "Yellow" } else { "Green" })
    
    # Test directly on DC
    Write-Host ""
    Write-Host "Directly on $DcName (localhost):" -ForegroundColor Yellow
    $remoteTimes = Invoke-Command -ComputerName $DcName -ScriptBlock {
        param($domain)
        $times = @()
        for ($i = 1; $i -le 10; $i++) {
            $startTime = Get-Date
            $result = Resolve-DnsName -Name $domain -Server localhost -ErrorAction SilentlyContinue
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            $times += $duration
        }
        return $times
    } -ArgumentList $testDomain
    
    $remoteAvg = ($remoteTimes | Measure-Object -Average).Average
    $remoteMin = ($remoteTimes | Measure-Object -Minimum).Minimum
    $remoteMax = ($remoteTimes | Measure-Object -Maximum).Maximum
    
    Write-Host "  Avg: $([math]::Round($remoteAvg, 2))ms, Min: $([math]::Round($remoteMin, 2))ms, Max: $([math]::Round($remoteMax, 2))ms" -ForegroundColor $(if ($remoteAvg -gt 100) { "Red" } elseif ($remoteAvg -gt 50) { "Yellow" } else { "Green" })
    
    Write-Host ""
    $difference = $remoteAvg - $localAvg
    if ($difference -gt 50) {
        Write-Host "WARNING: Local queries are much slower than remote queries!" -ForegroundColor Red
        Write-Host "  Difference: $([math]::Round($difference, 2))ms" -ForegroundColor Red
        Write-Host "  This suggests a network or client-side problem" -ForegroundColor Yellow
    }
    elseif ($remoteAvg -gt 100) {
        Write-Host "WARNING: DNS resolution is slow even on the DC itself!" -ForegroundColor Red
        Write-Host "  This suggests a DNS service or AD database problem" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not test DNS query performance: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 7. AD Database Fragmentation Check
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "7. AD DATABASE FRAGMENTATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $fragInfo = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $ntdsPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters")."DSA Database file"
        $dbPath = $ntdsPath -replace "\\\\.*", ""
        
        if (Test-Path $dbPath) {
            $dbFile = Get-Item $dbPath
            $fileSize = $dbFile.Length
            
            # Check for fragmentation (simplified - actual fragmentation check requires esentutl)
            $drive = $dbFile.Directory.Root
            $driveInfo = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$drive'"
            
            return @{
                DatabasePath = $dbPath
                DatabaseSizeMB = [math]::Round($fileSize / 1MB, 2)
                DriveFreeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
                DriveTotalSpaceGB = [math]::Round($driveInfo.Size / 1GB, 2)
                FreeSpacePercent = [math]::Round(($driveInfo.FreeSpace / $driveInfo.Size) * 100, 2)
            }
        }
        return $null
    }
    
    if ($fragInfo) {
        Write-Host "Database Location:" -ForegroundColor Yellow
        Write-Host "  Path: $($fragInfo.DatabasePath)" -ForegroundColor White
        Write-Host "  Size: $($fragInfo.DatabaseSizeMB) MB" -ForegroundColor White
        Write-Host "  Drive Free Space: $($fragInfo.DriveFreeSpaceGB) GB ($($fragInfo.FreeSpacePercent)%)" -ForegroundColor White
        
        if ($fragInfo.FreeSpacePercent -lt 10) {
            Write-Host "WARNING: Low disk space on database drive!" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "Note: Detailed fragmentation analysis requires esentutl.exe" -ForegroundColor Yellow
        Write-Host "  Run: esentutl /ms \"$($fragInfo.DatabasePath)\" /d" -ForegroundColor White
    }
}
catch {
    Write-Host "ERROR: Could not check database fragmentation: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 8. Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "8. SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Key Findings:" -ForegroundColor Yellow
Write-Host "- AD Database size and location" -ForegroundColor White
Write-Host "- AD Database performance counters" -ForegroundColor White
Write-Host "- DNS Service resource usage" -ForegroundColor White
Write-Host "- System resource constraints" -ForegroundColor White
Write-Host "- Network latency" -ForegroundColor White
Write-Host "- DNS query performance (local vs remote)" -ForegroundColor White
Write-Host "- Database fragmentation indicators" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
