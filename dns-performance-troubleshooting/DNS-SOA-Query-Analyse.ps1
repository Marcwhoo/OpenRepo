# DNS SOA Query Detail Analysis
# Analyzes why SOA queries are slow (Type 6 queries)

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFile
)

if (-not (Test-Path $CsvFile)) {
    Write-Host "ERROR: CSV file not found: $CsvFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS SOA Query Detail Analysis" -ForegroundColor Cyan
Write-Host "File: $CsvFile" -ForegroundColor Yellow
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

# Filter SOA queries (Type 6)
$soaQueries = $queries | Where-Object { $_.QueryType -eq "6" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERY SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Total SOA Queries: $($soaQueries.Count)" -ForegroundColor White
$avgTime = ($soaQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$maxTime = ($soaQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$minTime = ($soaQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
$slowCount = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "Average Response Time: $([math]::Round($avgTime, 2)) ms" -ForegroundColor $(if ($avgTime -gt 50) { "Red" } elseif ($avgTime -gt 10) { "Yellow" } else { "White" })
Write-Host "Min Response Time: $([math]::Round($minTime, 2)) ms" -ForegroundColor White
Write-Host "Max Response Time: $([math]::Round($maxTime, 2)) ms" -ForegroundColor $(if ($maxTime -gt 100) { "Red" } else { "White" })
Write-Host "Slow Queries (>100ms): $slowCount" -ForegroundColor $(if ($slowCount -gt 0) { "Red" } else { "Green" })

# SOA queries by domain
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY DOMAIN" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaByDomain = $soaQueries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
    $domainQueries = $_.Group
    $avgTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $minTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
    
    [PSCustomObject]@{
        Domain = $_.Name
        QueryCount = $domainQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MinResponseTimeMs = [math]::Round($minTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        IsInternal = ($_.Name -like "*.<DOMAIN-FQDN>" -or $_.Name -eq "<DOMAIN-FQDN>" -or $_.Name -like "*.in-addr.arpa")
    }
} | Sort-Object AvgResponseTimeMs -Descending

$soaByDomain | Format-Table Domain, QueryCount, AvgResponseTimeMs, MinResponseTimeMs, MaxResponseTimeMs, IsInternal -AutoSize

# Slow SOA queries detail
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SLOW SOA QUERIES (>100ms)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$slowSoaQueries = $soaQueries | Where-Object { $_.ResponseTimeMs -gt 100 } | Sort-Object ResponseTimeMs -Descending

if ($slowSoaQueries.Count -gt 0) {
    Write-Host "Found $($slowSoaQueries.Count) slow SOA queries:" -ForegroundColor Yellow
    $slowSoaQueries | Format-Table ResponseTimeMs, QueryName, SourceIp, DnsServer, ResponseCode -AutoSize
} else {
    Write-Host "No slow SOA queries found (>100ms)" -ForegroundColor Green
}

# SOA queries by source
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY SOURCE IP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaBySource = $soaQueries | Group-Object SourceIp | ForEach-Object {
    $sourceQueries = $_.Group
    $avgTime = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    
    [PSCustomObject]@{
        SourceIp = $_.Name
        QueryCount = $sourceQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
    }
} | Sort-Object QueryCount -Descending

$soaBySource | Format-Table SourceIp, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize

# SOA queries by DNS server
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY DNS SERVER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaByServer = $soaQueries | Group-Object DnsServer | ForEach-Object {
    $serverQueries = $_.Group
    $avgTime = ($serverQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($serverQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    
    [PSCustomObject]@{
        DnsServer = $_.Name
        QueryCount = $serverQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
    }
} | Sort-Object AvgResponseTimeMs -Descending

$soaByServer | Format-Table DnsServer, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize

# Response time distribution for SOA
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERY RESPONSE TIME DISTRIBUTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$fast = ($soaQueries | Where-Object { $_.ResponseTimeMs -le 10 }).Count
$normal = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 10 -and $_.ResponseTimeMs -le 50 }).Count
$slow = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 50 -and $_.ResponseTimeMs -le 100 }).Count
$verySlow = ($soaQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "<= 10ms:   $fast ($([math]::Round(($fast / $soaQueries.Count) * 100, 2))%)" -ForegroundColor Green
Write-Host "10-50ms:   $normal ($([math]::Round(($normal / $soaQueries.Count) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "50-100ms:  $slow ($([math]::Round(($slow / $soaQueries.Count) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "> 100ms:   $verySlow ($([math]::Round(($verySlow / $soaQueries.Count) * 100, 2))%)" -ForegroundColor Red

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
