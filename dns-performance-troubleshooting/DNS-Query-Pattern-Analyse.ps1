# DNS Query Pattern Analysis
# Analyzes DNS query patterns from Wireshark CSV to identify slow queries and patterns

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFile
)

if (-not (Test-Path $CsvFile)) {
    Write-Host "ERROR: CSV file not found: $CsvFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Query Pattern Analysis" -ForegroundColor Cyan
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

# 1. Slowest Query Types
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. SLOWEST QUERY TYPES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$queryTypeStats = $queries | Group-Object QueryType | ForEach-Object {
    $typeQueries = $_.Group
    $avgTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($typeQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    [PSCustomObject]@{
        QueryType = $_.Name
        Count = $typeQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
    }
} | Sort-Object AvgResponseTimeMs -Descending

$queryTypeStats | Format-Table QueryType, Count, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries -AutoSize

# 2. Most Queried Domains (Top 30)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. MOST QUERIED DOMAINS (Top 30)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$domainStats = $queries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
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

$domainStats | Format-Table Domain, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries, IsInternal -AutoSize

# 3. Slowest Domains (Focus on Internal)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. SLOWEST DOMAINS (Focus: Internal)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$slowDomains = $queries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
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
} | Where-Object { $_.AvgResponseTimeMs -gt 50 -or $_.IsInternal } | Sort-Object AvgResponseTimeMs -Descending | Select-Object -First 30

$slowDomains | Format-Table Domain, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries, IsInternal -AutoSize

# 4. Internal vs External Performance
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. INTERNAL vs EXTERNAL PERFORMANCE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$internalQueries = $queries | Where-Object { 
    $_.QueryName -like "*.<DOMAIN-FQDN>" -or 
    $_.QueryName -eq "<DOMAIN-FQDN>" -or 
    $_.QueryName -like "*.in-addr.arpa" 
}

$externalQueries = $queries | Where-Object { 
    $_.QueryName -ne "" -and
    $_.QueryName -notlike "*.<DOMAIN-FQDN>" -and 
    $_.QueryName -ne "<DOMAIN-FQDN>" -and 
    $_.QueryName -notlike "*.in-addr.arpa" 
}

if ($internalQueries.Count -gt 0) {
    $internalAvg = ($internalQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $internalMax = ($internalQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $internalSlow = ($internalQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    Write-Host "INTERNAL Queries:" -ForegroundColor Yellow
    Write-Host "  Count: $($internalQueries.Count)" -ForegroundColor White
    Write-Host "  Avg Response Time: $([math]::Round($internalAvg, 2)) ms" -ForegroundColor $(if ($internalAvg -gt 50) { "Red" } elseif ($internalAvg -gt 10) { "Yellow" } else { "Green" })
    Write-Host "  Max Response Time: $([math]::Round($internalMax, 2)) ms" -ForegroundColor $(if ($internalMax -gt 100) { "Red" } else { "White" })
    Write-Host "  Slow Queries (>100ms): $internalSlow" -ForegroundColor $(if ($internalSlow -gt 0) { "Red" } else { "Green" })
}

if ($externalQueries.Count -gt 0) {
    $externalAvg = ($externalQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $externalMax = ($externalQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $externalSlow = ($externalQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    Write-Host ""
    Write-Host "EXTERNAL Queries:" -ForegroundColor Yellow
    Write-Host "  Count: $($externalQueries.Count)" -ForegroundColor White
    Write-Host "  Avg Response Time: $([math]::Round($externalAvg, 2)) ms" -ForegroundColor $(if ($externalAvg -gt 100) { "Red" } elseif ($externalAvg -gt 50) { "Yellow" } else { "Green" })
    Write-Host "  Max Response Time: $([math]::Round($externalMax, 2)) ms" -ForegroundColor $(if ($externalMax -gt 1000) { "Red" } else { "White" })
    Write-Host "  Slow Queries (>100ms): $externalSlow" -ForegroundColor $(if ($externalSlow -gt 0) { "Yellow" } else { "Green" })
}

# 5. Top Sources with Slow Queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. TOP SOURCES WITH SLOW QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$sourceStats = $queries | Group-Object SourceIp | ForEach-Object {
    $sourceQueries = $_.Group
    $avgTime = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($sourceQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    $internalCount = ($sourceQueries | Where-Object { 
        $_.QueryName -like "*.<DOMAIN-FQDN>" -or 
        $_.QueryName -eq "<DOMAIN-FQDN>" -or 
        $_.QueryName -like "*.in-addr.arpa" 
    }).Count
    
    [PSCustomObject]@{
        SourceIp = $_.Name
        TotalQueries = $sourceQueries.Count
        InternalQueries = $internalCount
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
    }
} | Where-Object { $_.SlowQueries -gt 0 -or $_.InternalQueries -gt 0 } | Sort-Object SlowQueries -Descending | Select-Object -First 20

$sourceStats | Format-Table SourceIp, TotalQueries, InternalQueries, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries -AutoSize

# 6. Response Time Distribution
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. RESPONSE TIME DISTRIBUTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$fast = ($queries | Where-Object { $_.ResponseTimeMs -le 10 }).Count
$normal = ($queries | Where-Object { $_.ResponseTimeMs -gt 10 -and $_.ResponseTimeMs -le 50 }).Count
$slow = ($queries | Where-Object { $_.ResponseTimeMs -gt 50 -and $_.ResponseTimeMs -le 100 }).Count
$verySlow = ($queries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "<= 10ms:   $fast ($([math]::Round(($fast / $queries.Count) * 100, 2))%)" -ForegroundColor Green
Write-Host "10-50ms:   $normal ($([math]::Round(($normal / $queries.Count) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "50-100ms:  $slow ($([math]::Round(($slow / $queries.Count) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "> 100ms:   $verySlow ($([math]::Round(($verySlow / $queries.Count) * 100, 2))%)" -ForegroundColor Red

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
