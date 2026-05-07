# DNS Wireshark Trace Analysis - Fast Version
# Uses tshark statistics for fast analysis without full matching

param(
    [Parameter(Mandatory=$true)]
    [string]$PcapngFile,
    [int]$SlowThresholdMs = 100,
    [int]$TopCount = 30
)

$tsharkPath = "C:\Program Files\Wireshark\tshark.exe"

if (-not (Test-Path $tsharkPath)) {
    Write-Host "ERROR: tshark.exe not found at $tsharkPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $PcapngFile)) {
    Write-Host "ERROR: pcapng file not found: $PcapngFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Wireshark Analysis - Fast" -ForegroundColor Cyan
Write-Host "File: $PcapngFile" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Basic Statistics
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. BASIC STATISTICS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Getting packet count..." -NoNewline
$packetCount = & $tsharkPath -r $PcapngFile -Y "dns" -T fields -e frame.number 2>&1 | Measure-Object -Line
Write-Host " OK ($($packetCount.Lines) DNS packets)" -ForegroundColor Green

# 2. Extract only slow queries (response time > threshold)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. EXTRACTING SLOW QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Extracting DNS conversations with timing..." -NoNewline
$fields = @(
    "frame.time_relative",
    "dns.id",
    "ip.src",
    "ip.dst",
    "dns.flags.response",
    "dns.flags.rcode",
    "dns.qry.name",
    "dns.qry.type"
)

$tsharkArgs = @("-r", $PcapngFile, "-Y", "dns", "-T", "fields")
foreach ($field in $fields) {
    $tsharkArgs += "-e"
    $tsharkArgs += $field
}

$rawData = & $tsharkPath $tsharkArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host " ERROR" -ForegroundColor Red
    Write-Host "Failed to extract data: $rawData" -ForegroundColor Red
    exit 1
}
Write-Host " OK" -ForegroundColor Green

# Helper function
function Normalize-DnsId {
    param([string]$dnsId)
    if ([string]::IsNullOrWhiteSpace($dnsId)) { return "" }
    if ($dnsId -match "^0x") {
        return [int]::Parse($dnsId.Substring(2), [System.Globalization.NumberStyles]::AllowHexSpecifier).ToString()
    }
    return $dnsId
}

# Parse and match (optimized)
Write-Host "Parsing and matching (this may take a while for large files)..." -ForegroundColor Yellow
$packets = New-Object System.Collections.ArrayList
$lineCount = 0

foreach ($line in $rawData) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $fields = $line -split "`t"
    if ($fields.Count -lt 6) { continue }
    
    $lineCount++
    if ($lineCount % 50000 -eq 0) {
        Write-Host "  Processed $lineCount packets..." -ForegroundColor Yellow
    }
    
    try {
        $dnsId = if ($fields[1]) { Normalize-DnsId $fields[1] } else { "" }
        $isResponse = if ($fields[4]) { $fields[4] -eq "True" -or $fields[4] -eq "1" } else { $false }
        
        $packet = [PSCustomObject]@{
            TimeRelative = if ($fields[0]) { [double]$fields[0] } else { 0 }
            DnsId = $dnsId
            IpSource = if ($fields[2]) { $fields[2] } else { "" }
            IpDestination = if ($fields[3]) { $fields[3] } else { "" }
            IsResponse = $isResponse
            ResponseCode = if ($fields[5]) { $fields[5] } else { "0" }
            QueryName = if ($fields[6]) { $fields[6] } else { "" }
            QueryType = if ($fields[7]) { $fields[7] } else { "" }
        }
        [void]$packets.Add($packet)
    }
    catch { }
}

Write-Host "Parsed $($packets.Count) packets" -ForegroundColor Green

# Quick match - only for slow queries
Write-Host "Matching requests with responses (optimized)..." -ForegroundColor Yellow
$requests = $packets | Where-Object { -not $_.IsResponse }
$responses = $packets | Where-Object { $_.IsResponse }

$responseIndex = @{}
foreach ($response in $responses) {
    if ([string]::IsNullOrWhiteSpace($response.DnsId)) { continue }
    $key = "$($response.DnsId)|$($response.IpSource)|$($response.IpDestination)"
    if (-not $responseIndex.ContainsKey($key)) {
        $responseIndex[$key] = New-Object System.Collections.ArrayList
    }
    [void]$responseIndex[$key].Add($response)
}

$keys = @($responseIndex.Keys)
foreach ($key in $keys) {
    $responseIndex[$key] = $responseIndex[$key] | Sort-Object TimeRelative
}

$matchedQueries = New-Object System.Collections.ArrayList
$requestCount = 0
$totalRequests = $requests.Count

Write-Host "Matching $totalRequests requests..." -ForegroundColor Yellow
foreach ($request in $requests) {
    $requestCount++
    if ($requestCount % 10000 -eq 0) {
        Write-Host "  Matched $requestCount / $totalRequests requests..." -ForegroundColor Yellow
    }
    
    if ([string]::IsNullOrWhiteSpace($request.DnsId)) { continue }
    $lookupKey = "$($request.DnsId)|$($request.IpDestination)|$($request.IpSource)"
    
    if ($responseIndex.ContainsKey($lookupKey)) {
        $responseList = $responseIndex[$lookupKey]
        $matchingResponse = $null
        
        foreach ($resp in $responseList) {
            if ($resp.TimeRelative -gt $request.TimeRelative) {
                $matchingResponse = $resp
                break
            }
        }
        
        if ($matchingResponse) {
            $responseTime = ($matchingResponse.TimeRelative - $request.TimeRelative) * 1000
            $matchedQuery = [PSCustomObject]@{
                ResponseTimeMs = [math]::Round($responseTime, 2)
                QueryName = $request.QueryName
                QueryType = $request.QueryType
                SourceIp = $request.IpSource
                DnsServer = $request.IpDestination
                ResponseCode = $matchingResponse.ResponseCode
            }
            [void]$matchedQueries.Add($matchedQuery)
        }
    }
}

Write-Host "Matched $($matchedQueries.Count) queries" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$totalQueries = $matchedQueries.Count
$avgResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$maxResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$slowQueries = ($matchedQueries | Where-Object { $_.ResponseTimeMs -gt $SlowThresholdMs }).Count

Write-Host "Total Queries: $totalQueries" -ForegroundColor White
Write-Host "Average Response Time: $([math]::Round($avgResponseTime, 2)) ms" -ForegroundColor White
Write-Host "Max Response Time: $([math]::Round($maxResponseTime, 2)) ms" -ForegroundColor $(if ($maxResponseTime -gt $SlowThresholdMs) { "Red" } else { "White" })
Write-Host "Slow Queries (>$SlowThresholdMs ms): $slowQueries" -ForegroundColor $(if ($slowQueries -gt 0) { "Yellow" } else { "Green" })

# Focus on INTERNAL queries only
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INTERNAL DNS QUERIES (RDS-RELEVANT)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$internalQueries = $matchedQueries | Where-Object { 
    $_.QueryName -like "*.<DOMAIN-FQDN>" -or 
    $_.QueryName -eq "<DOMAIN-FQDN>" -or 
    $_.QueryName -like "*.in-addr.arpa" 
}

Write-Host "Total Internal Queries: $($internalQueries.Count)" -ForegroundColor White
if ($internalQueries.Count -gt 0) {
    $internalAvg = ($internalQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $internalMax = ($internalQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $internalSlow = ($internalQueries | Where-Object { $_.ResponseTimeMs -gt $SlowThresholdMs }).Count
    
    Write-Host "Average Response Time: $([math]::Round($internalAvg, 2)) ms" -ForegroundColor $(if ($internalAvg -gt 50) { "Red" } elseif ($internalAvg -gt 10) { "Yellow" } else { "Green" })
    Write-Host "Max Response Time: $([math]::Round($internalMax, 2)) ms" -ForegroundColor $(if ($internalMax -gt 100) { "Red" } else { "White" })
    Write-Host "Slow Queries (>$SlowThresholdMs ms): $internalSlow" -ForegroundColor $(if ($internalSlow -gt 0) { "Red" } else { "Green" })
    
    Write-Host ""
    Write-Host "Top $TopCount slowest INTERNAL queries:" -ForegroundColor Yellow
    $internalQueries | Sort-Object ResponseTimeMs -Descending | Select-Object -First $TopCount | ForEach-Object {
        $color = if ($_.ResponseTimeMs -gt 1000) { "Red" } elseif ($_.ResponseTimeMs -gt $SlowThresholdMs) { "Yellow" } else { "White" }
        Write-Host "  $([math]::Round($_.ResponseTimeMs, 2)) ms | $($_.SourceIp) -> $($_.DnsServer) | $($_.QueryName) ($($_.QueryType))" -ForegroundColor $color
    }
}

# Top slow queries (all)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP $TopCount SLOWEST QUERIES (ALL)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$topSlow = $matchedQueries | Sort-Object ResponseTimeMs -Descending | Select-Object -First $TopCount
$topSlow | ForEach-Object {
    $color = if ($_.ResponseTimeMs -gt 1000) { "Red" } elseif ($_.ResponseTimeMs -gt $SlowThresholdMs) { "Yellow" } else { "White" }
    Write-Host "$([math]::Round($_.ResponseTimeMs, 2)) ms | $($_.SourceIp) -> $($_.DnsServer) | $($_.QueryName) ($($_.QueryType))" -ForegroundColor $color
}

# Top sources
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP $TopCount SOURCES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$sourceStats = $matchedQueries | Group-Object SourceIp | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($queries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    [PSCustomObject]@{
        SourceIp = $_.Name
        QueryCount = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object QueryCount -Descending | Select-Object -First $TopCount

$sourceStats | ForEach-Object {
    Write-Host "$($_.SourceIp): $($_.QueryCount) queries | Avg: $($_.AvgResponseTime) ms | Max: $($_.MaxResponseTime) ms" -ForegroundColor White
}

# DNS Server performance
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS SERVER PERFORMANCE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$serverStats = $matchedQueries | Group-Object DnsServer | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($queries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    [PSCustomObject]@{
        DnsServer = $_.Name
        QueryCount = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object AvgResponseTime -Descending

$serverStats | ForEach-Object {
    $color = if ($_.AvgResponseTime -gt 100) { "Red" } elseif ($_.AvgResponseTime -gt 50) { "Yellow" } else { "Green" }
    Write-Host "$($_.DnsServer): $($_.QueryCount) queries | Avg: $($_.AvgResponseTime) ms | Max: $($_.MaxResponseTime) ms" -ForegroundColor $color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
