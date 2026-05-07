# DNS Analysis - Focus on Slow Queries
# Analyzes which queries are slow and why

param(
    [Parameter(Mandatory=$true)]
    [string]$AnalysisCsv,
    [int]$SlowThresholdMs = 100
)

if (-not (Test-Path $AnalysisCsv)) {
    Write-Host "ERROR: Analysis CSV not found: $AnalysisCsv" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Slow Query Analysis" -ForegroundColor Cyan
Write-Host "File: $AnalysisCsv" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Import data
Write-Host "Loading data..." -NoNewline
$data = Import-Csv $AnalysisCsv
Write-Host " OK ($($data.Count) queries)" -ForegroundColor Green

# Filter slow queries
$slowQueries = $data | Where-Object { [double]$_.ResponseTimeMs -gt $SlowThresholdMs } | Sort-Object { [double]$_.ResponseTimeMs } -Descending

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SLOW QUERIES ANALYSIS (>$SlowThresholdMs ms)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total slow queries: $($slowQueries.Count)" -ForegroundColor $(if ($slowQueries.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# Group by Query Name
Write-Host "Slow queries by domain name:" -ForegroundColor Yellow
$byDomain = $slowQueries | Group-Object QueryName | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Average).Average
    $maxTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Maximum).Maximum
    [PSCustomObject]@{
        Domain = $_.Name
        Count = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object MaxResponseTime -Descending

$byDomain | Format-Table -AutoSize

# Group by DNS Server
Write-Host ""
Write-Host "Slow queries by DNS server:" -ForegroundColor Yellow
$byServer = $slowQueries | Group-Object DnsServer | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Average).Average
    $maxTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Maximum).Maximum
    [PSCustomObject]@{
        DnsServer = $_.Name
        Count = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object MaxResponseTime -Descending

$byServer | Format-Table -AutoSize

# Group by Source IP
Write-Host ""
Write-Host "Slow queries by source IP:" -ForegroundColor Yellow
$bySource = $slowQueries | Group-Object IpSource | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Average).Average
    $maxTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Maximum).Maximum
    [PSCustomObject]@{
        SourceIp = $_.Name
        Count = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object MaxResponseTime -Descending

$bySource | Format-Table -AutoSize

# Check if queries go to external DNS (8.8.8.8)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EXTERNAL DNS FORWARDING ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$externalQueries = $data | Where-Object { $_.DnsServer -eq "8.8.8.8" }
$externalSlow = $externalQueries | Where-Object { [double]$_.ResponseTimeMs -gt $SlowThresholdMs }

Write-Host "Total queries to 8.8.8.8: $($externalQueries.Count)" -ForegroundColor White
Write-Host "Slow queries to 8.8.8.8: $($externalSlow.Count)" -ForegroundColor $(if ($externalSlow.Count -gt 0) { "Yellow" } else { "Green" })
if ($externalQueries.Count -gt 0) {
    $extAvg = ($externalQueries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Average).Average
    $extMax = ($externalQueries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Maximum).Maximum
    Write-Host "Average response time (8.8.8.8): $([math]::Round($extAvg, 2)) ms" -ForegroundColor White
    Write-Host "Max response time (8.8.8.8): $([math]::Round($extMax, 2)) ms" -ForegroundColor $(if ($extMax -gt 1000) { "Red" } else { "White" })
}

# Top domains forwarded to 8.8.8.8
Write-Host ""
Write-Host "Top domains forwarded to 8.8.8.8:" -ForegroundColor Yellow
$topForwarded = $externalQueries | Group-Object QueryName | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Average).Average
    $maxTime = ($queries | ForEach-Object { [double]$_.ResponseTimeMs } | Measure-Object -Maximum).Maximum
    [PSCustomObject]@{
        Domain = $_.Name
        Count = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object Count -Descending | Select-Object -First 20

$topForwarded | Format-Table -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Check DNS Forwarders configuration on DC" -ForegroundColor Yellow
Write-Host "   - Why is 8.8.8.8 used for so many queries?" -ForegroundColor White
Write-Host "   - Are forwarders configured correctly?" -ForegroundColor White
Write-Host ""
Write-Host "2. Check DNS Cache" -ForegroundColor Yellow
Write-Host "   - Are frequently queried domains cached?" -ForegroundColor White
Write-Host "   - Check cache hit rate" -ForegroundColor White
Write-Host ""
Write-Host "3. Check DNS Zone Configuration" -ForegroundColor Yellow
Write-Host "   - Are internal domains properly configured?" -ForegroundColor White
Write-Host "   - Are external queries necessary?" -ForegroundColor White
Write-Host ""
Write-Host "4. Network connectivity to 8.8.8.8" -ForegroundColor Yellow
Write-Host "   - Check latency to 8.8.8.8" -ForegroundColor White
Write-Host "   - Check for packet loss" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
