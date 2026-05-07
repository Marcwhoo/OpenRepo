# DNS Cache Analysis Script
# Analyzes DNS cache configuration and behavior

param(
    [string]$DcName = "<DC-SERVER>",
    [int]$ObservationSeconds = 60
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Cache Analysis" -ForegroundColor Cyan
Write-Host "Domain Controller: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. DNS Cache Configuration
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. DNS CACHE CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $cacheConfig = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $dnsServer = Get-DnsServerSetting -All
        $cacheSettings = $dnsServer | Where-Object { 
            $_.Name -like "*Cache*" -or 
            $_.Name -like "*TTL*" -or 
            $_.Name -like "*Scavenging*" 
        }
        return $cacheSettings
    }
    
    if ($cacheConfig) {
        Write-Host "Cache Configuration:" -ForegroundColor Yellow
        $cacheConfig | Format-Table -AutoSize
    }
    else {
        Write-Host "No specific cache configuration found" -ForegroundColor Yellow
    }
    
    # Check cache size limit
    $cacheSize = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters"
        if (Test-Path $regPath) {
            $cacheSize = Get-ItemProperty -Path $regPath -Name "MaxCacheTTL" -ErrorAction SilentlyContinue
            $negativeCache = Get-ItemProperty -Path $regPath -Name "MaxNegativeCacheTTL" -ErrorAction SilentlyContinue
            return @{
                MaxCacheTTL = if ($cacheSize) { $cacheSize.MaxCacheTTL } else { "Not set (default)" }
                MaxNegativeCacheTTL = if ($negativeCache) { $negativeCache.MaxNegativeCacheTTL } else { "Not set (default)" }
            }
        }
        return $null
    }
    
    if ($cacheSize) {
        Write-Host ""
        Write-Host "Cache TTL Settings:" -ForegroundColor Yellow
        Write-Host "  MaxCacheTTL: $($cacheSize.MaxCacheTTL)" -ForegroundColor White
        Write-Host "  MaxNegativeCacheTTL: $($cacheSize.MaxNegativeCacheTTL)" -ForegroundColor White
    }
}
catch {
    Write-Host "ERROR: Could not check cache configuration: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 2. Current Cache State
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. CURRENT CACHE STATE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $cacheEntries = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerCache
    }
    
    Write-Host "Cache Entries: $($cacheEntries.Count)" -ForegroundColor Yellow
    
    if ($cacheEntries.Count -gt 0) {
        Write-Host ""
        Write-Host "Sample Cache Entries (first 20):" -ForegroundColor Yellow
        $cacheEntries | Select-Object -First 20 | Format-Table HostName, RecordType, TimeToLive, DataLength -AutoSize
        
        $cacheStats = $cacheEntries | Group-Object RecordType | ForEach-Object {
            [PSCustomObject]@{
                RecordType = $_.Name
                Count = $_.Count
            }
        } | Sort-Object Count -Descending
        
        Write-Host ""
        Write-Host "Cache by Record Type:" -ForegroundColor Yellow
        $cacheStats | Format-Table -AutoSize
    }
    else {
        Write-Host "WARNING: Cache is empty!" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: Could not check cache state: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 3. Cache Observation during Active Traffic
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. CACHE OBSERVATION ($ObservationSeconds seconds)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Observing cache during active traffic..." -ForegroundColor Yellow
Write-Host ""

try {
    $initialCache = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerCache | Measure-Object | Select-Object Count
    }
    Write-Host "Initial cache entries: $($initialCache.Count)" -ForegroundColor White
    
    # Trigger some DNS queries
    Write-Host "Triggering DNS queries..." -ForegroundColor Yellow
    $testDomains = @(
        "google.com",
        "microsoft.com",
        "<DOMAIN-FQDN>",
        "<DC-SERVER>.<DOMAIN-FQDN>",
        "<DC-SERVER>.<DOMAIN-FQDN>"
    )
    
    foreach ($domain in $testDomains) {
        Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($d)
            Resolve-DnsName -Name $d -Server localhost -ErrorAction SilentlyContinue | Out-Null
        } -ArgumentList $domain | Out-Null
        Start-Sleep -Milliseconds 100
    }
    
    Start-Sleep -Seconds 2
    
    $afterQueriesCache = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerCache | Measure-Object | Select-Object Count
    }
    Write-Host "Cache entries after queries: $($afterQueriesCache.Count)" -ForegroundColor White
    
    if ($afterQueriesCache.Count -gt $initialCache.Count) {
        $newEntries = $afterQueriesCache.Count - $initialCache.Count
        Write-Host "New cache entries: $newEntries" -ForegroundColor Green
    }
    else {
        Write-Host "WARNING: No new cache entries created!" -ForegroundColor Red
    }
    
    # Observe cache for specified duration
    Write-Host ""
    Write-Host "Observing cache for $ObservationSeconds seconds..." -ForegroundColor Yellow
    $cacheHistory = @()
    $startTime = Get-Date
    
    for ($i = 0; $i -lt $ObservationSeconds; $i += 5) {
        $cacheCount = Invoke-Command -ComputerName $DcName -ScriptBlock {
            (Get-DnsServerCache | Measure-Object).Count
        }
        
        $cacheHistory += [PSCustomObject]@{
            Time = (Get-Date) - $startTime
            CacheEntries = $cacheCount
        }
        
        Write-Host "  $i seconds: $cacheCount cache entries" -ForegroundColor White
        Start-Sleep -Seconds 5
    }
    
    Write-Host ""
    Write-Host "Cache Observation Summary:" -ForegroundColor Yellow
    $cacheHistory | Format-Table -AutoSize
    
    $finalCache = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerCache | Measure-Object | Select-Object Count
    }
    Write-Host "Final cache entries: $($finalCache.Count)" -ForegroundColor White
}
catch {
    Write-Host "ERROR: Could not observe cache: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 4. DNS Zone Details for <DOMAIN-FQDN>
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. DNS ZONE DETAILS - <DOMAIN-FQDN>" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $zoneDetails = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerZone -Name "<DOMAIN-FQDN>" | Select-Object *
    }
    
    Write-Host "Zone Configuration:" -ForegroundColor Yellow
    $zoneDetails | Format-List ZoneName, ZoneType, DynamicUpdate, Aging, Paused, Loaded, ZoneFile
    
    $zoneRecords = Invoke-Command -ComputerName $DcName -ScriptBlock {
        Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" | Select-Object HostName, RecordType, TimeToLive, @{Name="RecordData";Expression={$_.RecordData.IPv4Address -or $_.RecordData.NameServer -or $_.RecordData.ToString()}}
    }
    
    Write-Host ""
    Write-Host "Zone Records (first 20):" -ForegroundColor Yellow
    $zoneRecords | Select-Object -First 20 | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Total Records in Zone: $($zoneRecords.Count)" -ForegroundColor White
    
    $recordTypes = $zoneRecords | Group-Object RecordType | ForEach-Object {
        [PSCustomObject]@{
            RecordType = $_.Name
            Count = $_.Count
        }
    } | Sort-Object Count -Descending
    
    Write-Host ""
    Write-Host "Records by Type:" -ForegroundColor Yellow
    $recordTypes | Format-Table -AutoSize
    
    # Check for SOA record
    $soaRecord = $zoneRecords | Where-Object { $_.RecordType -eq "SOA" }
    if ($soaRecord) {
        Write-Host ""
        Write-Host "SOA Record Details:" -ForegroundColor Yellow
        $soaDetails = Invoke-Command -ComputerName $DcName -ScriptBlock {
            $soa = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -RRType SOA
            return $soa.RecordData
        }
        $soaDetails | Format-List
    }
}
catch {
    Write-Host "ERROR: Could not check zone details: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. DNS Resolution Performance Test
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. DNS RESOLUTION PERFORMANCE TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $testDomains = @(
        "<DOMAIN-FQDN>",
        "<DC-SERVER>.<DOMAIN-FQDN>",
        "<DC-SERVER>.<DOMAIN-FQDN>"
    )
    
    foreach ($domain in $testDomains) {
        Write-Host "Testing: $domain" -NoNewline
        $times = @()
        
        for ($i = 1; $i -le 10; $i++) {
            $startTime = Get-Date
            $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
                param($d)
                Resolve-DnsName -Name $d -Server localhost -ErrorAction SilentlyContinue
            } -ArgumentList $domain
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            $times += $duration
        }
        
        $avg = ($times | Measure-Object -Average).Average
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        
        $color = if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" }
        Write-Host " - Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $color
        
        if ($result) {
            Write-Host "  Result: $($result[0].IPAddress)" -ForegroundColor White
        }
    }
}
catch {
    Write-Host "ERROR: Could not test resolution performance: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 6. Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Key Findings:" -ForegroundColor Yellow
Write-Host "- DNS Cache state and configuration" -ForegroundColor White
Write-Host "- Cache behavior during active traffic" -ForegroundColor White
Write-Host "- <DOMAIN-FQDN> zone details" -ForegroundColor White
Write-Host "- DNS resolution performance" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
