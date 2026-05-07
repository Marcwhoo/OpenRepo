# DNS Comprehensive Diagnosis Script
# Checks all DNS components on Domain Controller

param(
    [string]$DcName = "<DC-SERVER>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Comprehensive Diagnosis" -ForegroundColor Cyan
Write-Host "Domain Controller: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. DNS Service Status
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. DNS SERVICE STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $dnsService = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-Service -Name "DNS" | Select-Object Name, Status, StartType, DisplayName
    }
    Write-Host "DNS Service Status:" -ForegroundColor Yellow
    $dnsService | Format-List
    if ($dnsService.Status -ne "Running") {
        Write-Host "WARNING: DNS Service is not running!" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: Could not check DNS service: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 2. DNS Zones Configuration
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. DNS ZONES CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $zones = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerZone | Select-Object ZoneName, ZoneType, IsAutoCreated, IsReverseLookupZone, IsSigned, DynamicUpdate
    }
    Write-Host "DNS Zones:" -ForegroundColor Yellow
    $zones | Format-Table -AutoSize
    
    $domainZone = $zones | Where-Object { $_.ZoneName -like "*<domain>*" -or $_.ZoneName -like "*<subdomain>*" -or $_.ZoneName -eq "<DOMAIN-FQDN>" }
    if ($domainZone) {
        Write-Host ""
        Write-Host "<DOMAIN-FQDN> Zone Details:" -ForegroundColor Yellow
        $domainZone | Format-List
        
        $zoneDetails = Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($zoneName)
            Get-DnsServerZone -Name $zoneName | Select-Object *
        } -ArgumentList $domainZone.ZoneName
        Write-Host "Zone Configuration:" -ForegroundColor Yellow
        $zoneDetails | Format-List ZoneName, ZoneType, DynamicUpdate, Aging, Paused, Loaded
    }
    else {
        Write-Host "WARNING: <DOMAIN-FQDN> zone not found!" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: Could not check DNS zones: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 3. DNS Forwarders
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. DNS FORWARDERS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $forwarders = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerForwarder | Select-Object IPAddress, UseRootHint, Timeout
    }
    Write-Host "DNS Forwarders:" -ForegroundColor Yellow
    if ($forwarders) {
        $forwarders | Format-Table -AutoSize
        
        foreach ($forwarder in $forwarders) {
            Write-Host "Testing connectivity to $($forwarder.IPAddress)..." -NoNewline
            $ping = Test-Connection -ComputerName $forwarder.IPAddress -Count 4 -ErrorAction SilentlyContinue
            if ($ping) {
                $avgLatency = ($ping | Measure-Object -Property ResponseTime -Average).Average
                Write-Host " OK (Avg: $([math]::Round($avgLatency, 2)) ms)" -ForegroundColor Green
            }
            else {
                Write-Host " FAILED" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "No forwarders configured (using root hints)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not check DNS forwarders: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 4. DNS Cache
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. DNS CACHE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $cache = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerCache | Measure-Object | Select-Object Count
    }
    Write-Host "DNS Cache Entries: $($cache.Count)" -ForegroundColor Yellow
    
    $cacheStats = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $stats = Get-DnsServerStatistics
        $cacheStats = $stats | Where-Object { $_.Name -like "*Cache*" }
        return $cacheStats
    }
    if ($cacheStats) {
        Write-Host "Cache Statistics:" -ForegroundColor Yellow
        $cacheStats | Format-Table -AutoSize
    }
}
catch {
    Write-Host "ERROR: Could not check DNS cache: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. Reverse DNS Zones
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. REVERSE DNS ZONES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $reverseZones = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone -eq $true } | Select-Object ZoneName, ZoneType, DynamicUpdate
    }
    if ($reverseZones) {
        Write-Host "Reverse DNS Zones:" -ForegroundColor Yellow
        $reverseZones | Format-Table -AutoSize
        
        $problemZone = $reverseZones | Where-Object { $_.ZoneName -like "<REVERSE-ZONE-PATTERN>" }
        if ($problemZone) {
            Write-Host ""
            Write-Host "Problem Zone (<REVERSE-ZONE>) Details:" -ForegroundColor Yellow
            $problemZone | Format-List
        }
    }
    else {
        Write-Host "No reverse DNS zones found" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: Could not check reverse DNS zones: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 6. DNS Performance Counters
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. DNS PERFORMANCE COUNTERS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $perfCounters = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $counters = @(
            "\DNS\Total Query Received",
            "\DNS\Total Response Sent",
            "\DNS\Total Response Received",
            "\DNS\Total Query Received/sec",
            "\DNS\Total Response Sent/sec",
            "\DNS\Recursive Queries/sec",
            "\DNS\Recursive Query Failure/sec",
            "\DNS\Cache Hit Rate"
        )
        
        $results = @()
        foreach ($counter in $counters) {
            try {
                $value = (Get-Counter -Counter $counter -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
                $results += [PSCustomObject]@{
                    Counter = $counter
                    Value = $value
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
    Write-Host "Performance Counters:" -ForegroundColor Yellow
    $perfCounters | Format-Table -AutoSize
}
catch {
    Write-Host "ERROR: Could not check performance counters: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 7. DNS Event Logs (Errors/Warnings)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "7. DNS EVENT LOGS (Last 24h)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $events = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $since = (Get-Date).AddHours(-24)
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DNS-Server'; Level=2,3; StartTime=$since} -ErrorAction SilentlyContinue | 
            Select-Object -First 20 TimeCreated, Id, LevelDisplayName, Message
    }
    if ($events) {
        Write-Host "DNS Errors/Warnings (last 24h):" -ForegroundColor Yellow
        $events | Format-Table -AutoSize
    }
    else {
        Write-Host "No DNS errors/warnings in last 24h" -ForegroundColor Green
    }
}
catch {
    Write-Host "ERROR: Could not check event logs: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 8. Test DNS Resolution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "8. DNS RESOLUTION TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $testDomains = @("<DOMAIN-FQDN>", "<DC-SERVER>.<DOMAIN-FQDN>", "<DC-SERVER>.<DOMAIN-FQDN>")
    
    foreach ($domain in $testDomains) {
        Write-Host "Testing: $domain" -NoNewline
        $startTime = Get-Date
        $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($d)
            Resolve-DnsName -Name $d -Server localhost -ErrorAction SilentlyContinue
        } -ArgumentList $domain
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        if ($result) {
            $color = if ($duration -gt 100) { "Red" } elseif ($duration -gt 50) { "Yellow" } else { "Green" }
            Write-Host " - OK ($([math]::Round($duration, 2)) ms)" -ForegroundColor $color
            Write-Host "  Result: $($result[0].IPAddress)" -ForegroundColor White
        }
        else {
            Write-Host " - FAILED" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "ERROR: Could not test DNS resolution: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 9. System Resources
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "9. SYSTEM RESOURCES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $resources = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $mem = Get-Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue
        $dnsProcess = Get-Process -Name "dns" -ErrorAction SilentlyContinue
        
        [PSCustomObject]@{
            CPUPercent = if ($cpu) { [math]::Round($cpu.CounterSamples[0].CookedValue, 2) } else { "N/A" }
            AvailableMemoryMB = if ($mem) { [math]::Round($mem.CounterSamples[0].CookedValue, 0) } else { "N/A" }
            DnsProcessMemoryMB = if ($dnsProcess) { [math]::Round($dnsProcess.WorkingSet64 / 1MB, 2) } else { "N/A" }
            DnsProcessCPU = if ($dnsProcess) { [math]::Round($dnsProcess.CPU, 2) } else { "N/A" }
        }
    }
    Write-Host "System Resources:" -ForegroundColor Yellow
    $resources | Format-List
}
catch {
    Write-Host "ERROR: Could not check system resources: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 10. Summary and Recommendations
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "10. SUMMARY AND RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Based on the analysis, check:" -ForegroundColor Yellow
Write-Host "1. Why <DOMAIN-FQDN> resolution takes 456ms (should be <10ms)" -ForegroundColor White
Write-Host "2. Why reverse DNS (<REVERSE-ZONE>) takes 421ms" -ForegroundColor White
Write-Host "3. DNS Zone configuration for <DOMAIN-FQDN>" -ForegroundColor White
Write-Host "4. DNS Service performance and resource usage" -ForegroundColor White
Write-Host "5. Network connectivity between DC and clients" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Diagnosis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
