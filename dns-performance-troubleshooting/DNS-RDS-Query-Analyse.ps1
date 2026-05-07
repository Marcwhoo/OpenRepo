# DNS RDS Query Analysis
# Analyzes which queries RDS hosts make and if they use WPAD/SOA

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFile,
    [string[]]$RdsHosts = @("<INTERNAL-SERVER>-rds01", "<INTERNAL-SERVER>-rds02", "<INTERNAL-SERVER>-rds03", "<INTERNAL-SERVER>-rds04")
)

if (-not (Test-Path $CsvFile)) {
    Write-Host "ERROR: CSV file not found: $CsvFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS RDS Query Analysis" -ForegroundColor Cyan
Write-Host "File: $CsvFile" -ForegroundColor Yellow
Write-Host "RDS Hosts: $($RdsHosts -join ', ')" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Loading CSV data..." -NoNewline
$queries = Import-Csv $CsvFile
Write-Host " OK ($($queries.Count) queries)" -ForegroundColor Green

Write-Host "Converting response times..." -NoNewline
$queries = $queries | ForEach-Object {
    $rt = $_.ResponseTimeMs -replace ',', '.'
    $_.ResponseTimeMs = [double]$rt
    $_
}
Write-Host " OK" -ForegroundColor Green

# Resolve RDS hostnames to IPs
Write-Host ""
Write-Host "Resolving RDS hostnames to IPs..." -ForegroundColor Yellow
$rdsIps = @{}
foreach ($rdsHostName in $RdsHosts) {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($rdsHostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1 -ExpandProperty IPAddressToString
        if ($ip) {
            $rdsIps[$ip] = $rdsHostName
            Write-Host "  $rdsHostName -> $ip" -ForegroundColor White
        }
    } catch {
        Write-Host "  $rdsHostName -> Could not resolve" -ForegroundColor Yellow
    }
}

if ($rdsIps.Count -eq 0) {
    Write-Host "WARNING: No RDS IPs found - trying to find RDS IPs in query data..." -ForegroundColor Yellow
    $possibleRdsIps = $queries | Group-Object IpSource | Where-Object { $_.Count -gt 100 } | Select-Object -First 10 Name
    Write-Host "Possible RDS IPs (top sources):" -ForegroundColor Yellow
    foreach ($ip in $possibleRdsIps) {
        Write-Host "  $($ip.Name)" -ForegroundColor White
    }
}

# Filter queries from RDS hosts
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QUERIES FROM RDS HOSTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$rdsQueries = $queries | Where-Object { $_.IpSource -and $rdsIps.ContainsKey($_.IpSource) }

if ($rdsQueries.Count -eq 0) {
    Write-Host "No queries found from RDS hosts in this trace" -ForegroundColor Yellow
    Write-Host "This might be because:" -ForegroundColor Yellow
    Write-Host "  - RDS hosts query different DNS servers" -ForegroundColor White
    Write-Host "  - RDS hosts were not active during trace" -ForegroundColor White
    Write-Host "  - RDS host IPs are different" -ForegroundColor White
    Write-Host ""
    Write-Host "Showing all source IPs with query counts:" -ForegroundColor Yellow
    $allSources = $queries | Group-Object IpSource | Sort-Object Count -Descending | Select-Object -First 20
    $allSources | Format-Table Name, Count -AutoSize
    exit 0
}

Write-Host "Total Queries from RDS hosts: $($rdsQueries.Count)" -ForegroundColor White
$avg = ($rdsQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$max = ($rdsQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$min = ($rdsQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
$slow = ($rdsQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "Average Response Time: $([math]::Round($avg, 2))ms" -ForegroundColor $(if ($avg -gt 50) { "Red" } elseif ($avg -gt 10) { "Yellow" } else { "White" })
Write-Host "Min Response Time: $([math]::Round($min, 2))ms" -ForegroundColor White
Write-Host "Max Response Time: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($max -gt 100) { "Red" } else { "White" })
Write-Host "Slow Queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Red" } else { "Green" })

# Check for WPAD queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WPAD QUERIES FROM RDS HOSTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$wpadQueries = $rdsQueries | Where-Object { $_.QueryName -and $_.QueryName -like "*wpad*" }

if ($wpadQueries.Count -gt 0) {
    Write-Host "Found $($wpadQueries.Count) WPAD queries from RDS hosts!" -ForegroundColor Red
    $wpadAvg = ($wpadQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $wpadMax = ($wpadQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $wpadSlow = ($wpadQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    Write-Host "  Average: $([math]::Round($wpadAvg, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($wpadMax, 2))ms" -ForegroundColor White
    Write-Host "  Slow Queries (>100ms): $wpadSlow" -ForegroundColor $(if ($wpadSlow -gt 0) { "Red" } else { "Green" })
    
    Write-Host ""
    Write-Host "WPAD queries by RDS host:" -ForegroundColor Yellow
    $wpadByHost = $wpadQueries | Group-Object SourceIp | ForEach-Object {
        $hostQueries = $_.Group
        $hostName = if ($rdsIps.ContainsKey($_.Name)) { $rdsIps[$_.Name] } else { $_.Name }
        $avgTime = ($hostQueries | Measure-Object -Property ResponseTimeMs -Average).Average
        $maxTime = ($hostQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
        
        [PSCustomObject]@{
            RdsHost = $hostName
            RdsIp = $_.Name
            QueryCount = $hostQueries.Count
            AvgResponseTimeMs = [math]::Round($avgTime, 2)
            MaxResponseTimeMs = [math]::Round($maxTime, 2)
        }
    } | Sort-Object QueryCount -Descending
    
    $wpadByHost | Format-Table RdsHost, RdsIp, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
} else {
    Write-Host "No WPAD queries found from RDS hosts" -ForegroundColor Green
}

# Check for SOA queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES FROM RDS HOSTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaQueries = $rdsQueries | Where-Object { $_.QueryType -and $_.QueryType -eq "6" }

if ($soaQueries.Count -gt 0) {
    Write-Host "Found $($soaQueries.Count) SOA queries from RDS hosts!" -ForegroundColor Red
    $soaAvg = ($soaQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $soaMax = ($soaQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $soaSlow = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    Write-Host "  Average: $([math]::Round($soaAvg, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($soaMax, 2))ms" -ForegroundColor White
    Write-Host "  Slow Queries (>100ms): $soaSlow" -ForegroundColor $(if ($soaSlow -gt 0) { "Red" } else { "Green" })
    
    Write-Host ""
    Write-Host "SOA queries by RDS host:" -ForegroundColor Yellow
    $soaByHost = $soaQueries | Group-Object IpSource | ForEach-Object {
        $hostQueries = $_.Group
        $hostName = if ($rdsIps.ContainsKey($_.Name)) { $rdsIps[$_.Name] } else { $_.Name }
        $avgTime = ($hostQueries | Measure-Object -Property ResponseTimeMs -Average).Average
        $maxTime = ($hostQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
        
        [PSCustomObject]@{
            RdsHost = $hostName
            RdsIp = $_.Name
            QueryCount = $hostQueries.Count
            AvgResponseTimeMs = [math]::Round($avgTime, 2)
            MaxResponseTimeMs = [math]::Round($maxTime, 2)
        }
    } | Sort-Object QueryCount -Descending
    
    $soaByHost | Format-Table RdsHost, RdsIp, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
    
    Write-Host ""
    Write-Host "SOA queries by domain:" -ForegroundColor Yellow
    $soaByDomain = $soaQueries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
        $domainQueries = $_.Group
        $avgTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Average).Average
        $maxTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
        
        [PSCustomObject]@{
            Domain = $_.Name
            QueryCount = $domainQueries.Count
            AvgResponseTimeMs = [math]::Round($avgTime, 2)
            MaxResponseTimeMs = [math]::Round($maxTime, 2)
        }
    } | Sort-Object AvgResponseTimeMs -Descending
    
    $soaByDomain | Format-Table Domain, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
} else {
    Write-Host "No SOA queries found from RDS hosts" -ForegroundColor Green
}

# RDS queries by query type
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS QUERIES BY QUERY TYPE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$byType = $rdsQueries | Group-Object QueryType | ForEach-Object {
    $typeQueries = $_.Group
    $avgTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($typeQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    $typeName = switch ($_.Name) {
        "1" { "A" }
        "2" { "NS" }
        "6" { "SOA" }
        "12" { "PTR" }
        "15" { "MX" }
        "16" { "TXT" }
        "28" { "AAAA" }
        "33" { "SRV" }
        "65" { "HTTPS" }
        default { $_.Name }
    }
    
    [PSCustomObject]@{
        QueryType = $typeName
        QueryTypeCode = $_.Name
        QueryCount = $typeQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
    }
} | Sort-Object QueryCount -Descending

$byType | Format-Table QueryType, QueryTypeCode, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries -AutoSize

# RDS queries by domain (top 30)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP 30 DOMAINS QUERIED BY RDS HOSTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$byDomain = $rdsQueries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
    $domainQueries = $_.Group
    $avgTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($domainQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    [PSCustomObject]@{
        Domain = $_.Name
        QueryCount = $domainQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
        IsInternal = ($_.Name -like "*.<DOMAIN-FQDN>" -or $_.Name -eq "<DOMAIN-FQDN>" -or $_.Name -like "*.in-addr.arpa")
    }
} | Sort-Object QueryCount -Descending | Select-Object -First 30

$byDomain | Format-Table Domain, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries, IsInternal -AutoSize

# Slow RDS queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SLOW RDS QUERIES (>100ms)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$slowRdsQueries = $rdsQueries | Where-Object { $_.ResponseTimeMs -gt 100 } | Sort-Object ResponseTimeMs -Descending

if ($slowRdsQueries.Count -gt 0) {
    Write-Host "Found $($slowRdsQueries.Count) slow queries from RDS hosts:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Top 30 slowest:" -ForegroundColor Yellow
    $slowRdsQueries | Select-Object -First 30 | Format-Table ResponseTimeMs, QueryName, QueryType, IpSource, DnsServer -AutoSize
} else {
    Write-Host "No slow queries found from RDS hosts" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "RDS Hosts using WPAD: $(if ($wpadQueries.Count -gt 0) { 'YES - PROBLEM!' } else { 'NO' })" -ForegroundColor $(if ($wpadQueries.Count -gt 0) { "Red" } else { "Green" })
Write-Host "RDS Hosts using SOA: $(if ($soaQueries.Count -gt 0) { 'YES - PROBLEM!' } else { 'NO' })" -ForegroundColor $(if ($soaQueries.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Total slow RDS queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Red" } else { "Green" })

if ($wpadQueries.Count -gt 0) {
    $wpadSlowCount = ($wpadQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    if ($wpadSlowCount -gt 0) {
        Write-Host ""
        Write-Host "CONCLUSION: RDS hosts ARE using WPAD queries that are slow!" -ForegroundColor Red
        Write-Host "These queries contribute to the RDS login delay." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "CONCLUSION: RDS hosts use WPAD queries, but they are fast in this trace." -ForegroundColor Yellow
        Write-Host "However, WPAD queries may timeout (400-800ms) when no record exists." -ForegroundColor Yellow
    }
} elseif ($soaQueries.Count -gt 0) {
    $soaSlowCount = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    if ($soaSlowCount -gt 0) {
        Write-Host ""
        Write-Host "CONCLUSION: RDS hosts ARE using SOA queries that are slow!" -ForegroundColor Red
        Write-Host "These queries contribute to the RDS login delay." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "CONCLUSION: RDS hosts use SOA queries, but they are fast in this trace." -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "CONCLUSION: RDS hosts are NOT directly using WPAD/SOA queries in this trace." -ForegroundColor Green
    Write-Host "However, slow WPAD/SOA queries from other sources may still affect DNS performance." -ForegroundColor Yellow
    Write-Host "Note: This trace may not capture RDS login activity - check 1-hour trace for more data." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
