# DNS Source Performance Analysis
# Analyzes why <IP-ADDRESS> as source is slow (103.85ms avg)

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFile
)

if (-not (Test-Path $CsvFile)) {
    Write-Host "ERROR: CSV file not found: $CsvFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Source Performance Analysis" -ForegroundColor Cyan
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

# Filter queries from <IP-ADDRESS>
$sourceQueries = $queries | Where-Object { $_.SourceIp -eq "<IP-ADDRESS>" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QUERIES FROM <IP-ADDRESS>" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Total Queries: $($sourceQueries.Count)" -ForegroundColor White
$avg = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$max = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$min = ($sourceQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
$slow = ($sourceQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "Average Response Time: $([math]::Round($avg, 2))ms" -ForegroundColor $(if ($avg -gt 50) { "Red" } elseif ($avg -gt 10) { "Yellow" } else { "White" })
Write-Host "Min Response Time: $([math]::Round($min, 2))ms" -ForegroundColor White
Write-Host "Max Response Time: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($max -gt 1000) { "Red" } else { "White" })
Write-Host "Slow Queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Red" } else { "Green" })

# Queries by DNS Server
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QUERIES BY DNS SERVER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$byServer = $sourceQueries | Group-Object DnsServer | ForEach-Object {
    $serverQueries = $_.Group
    $avgTime = ($serverQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($serverQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($serverQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    [PSCustomObject]@{
        DnsServer = $_.Name
        QueryCount = $serverQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
        IsInternal = ($_.Name -eq "<IP-ADDRESS>")
    }
} | Sort-Object AvgResponseTimeMs -Descending

$byServer | Format-Table DnsServer, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries, IsInternal -AutoSize

# Queries by Query Type
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QUERIES BY QUERY TYPE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$byType = $sourceQueries | Group-Object QueryType | ForEach-Object {
    $typeQueries = $_.Group
    $avgTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($typeQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($typeQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    [PSCustomObject]@{
        QueryType = $_.Name
        QueryCount = $typeQueries.Count
        AvgResponseTimeMs = [math]::Round($avgTime, 2)
        MaxResponseTimeMs = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
    }
} | Sort-Object AvgResponseTimeMs -Descending

$byType | Format-Table QueryType, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs, SlowQueries -AutoSize

# Internal vs External Queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INTERNAL vs EXTERNAL QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$internal = $sourceQueries | Where-Object { 
    $_.QueryName -like "*.<DOMAIN-FQDN>" -or 
    $_.QueryName -eq "<DOMAIN-FQDN>" -or 
    $_.QueryName -like "*.in-addr.arpa" 
}

$external = $sourceQueries | Where-Object { 
    $_.QueryName -ne "" -and
    $_.QueryName -notlike "*.<DOMAIN-FQDN>" -and 
    $_.QueryName -ne "<DOMAIN-FQDN>" -and 
    $_.QueryName -notlike "*.in-addr.arpa" 
}

if ($internal.Count -gt 0) {
    $internalAvg = ($internal | Measure-Object -Property ResponseTimeMs -Average).Average
    $internalMax = ($internal | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    Write-Host "INTERNAL Queries: $($internal.Count)" -ForegroundColor Yellow
    Write-Host "  Avg: $([math]::Round($internalAvg, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($internalMax, 2))ms" -ForegroundColor White
}

if ($external.Count -gt 0) {
    $externalAvg = ($external | Measure-Object -Property ResponseTimeMs -Average).Average
    $externalMax = ($external | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    Write-Host ""
    Write-Host "EXTERNAL Queries: $($external.Count)" -ForegroundColor Yellow
    Write-Host "  Avg: $([math]::Round($externalAvg, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($externalMax, 2))ms" -ForegroundColor White
}

# Slow Queries Detail
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SLOW QUERIES (>100ms) FROM <IP-ADDRESS>" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$slowQueries = $sourceQueries | Where-Object { $_.ResponseTimeMs -gt 100 } | Sort-Object ResponseTimeMs -Descending

if ($slowQueries.Count -gt 0) {
    Write-Host "Found $($slowQueries.Count) slow queries:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Top 30 slowest:" -ForegroundColor Yellow
    $slowQueries | Select-Object -First 30 | Format-Table ResponseTimeMs, QueryName, QueryType, DnsServer -AutoSize
    
    Write-Host ""
    Write-Host "Slow queries by domain:" -ForegroundColor Yellow
    $slowByDomain = $slowQueries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
        $domainQueries = $_.Group
        $avgTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Average).Average
        $maxTime = ($domainQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
        
        [PSCustomObject]@{
            Domain = $_.Name
            QueryCount = $domainQueries.Count
            AvgResponseTimeMs = [math]::Round($avgTime, 2)
            MaxResponseTimeMs = [math]::Round($maxTime, 2)
        }
    } | Sort-Object AvgResponseTimeMs -Descending | Select-Object -First 20
    
    $slowByDomain | Format-Table Domain, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
} else {
    Write-Host "No slow queries found" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
