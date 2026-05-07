# DNS Wireshark Trace Analysis - Slim Version
# Focus: High response times, request sources, DNS server performance

param(
    [Parameter(Mandatory=$true)]
    [string]$PcapngFile,
    [int]$SlowThresholdMs = 100,
    [int]$TopCount = 20
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
Write-Host "DNS Wireshark Analysis - Slim" -ForegroundColor Cyan
Write-Host "File: $PcapngFile" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Extract DNS packets
Write-Host "Extracting DNS packets..." -NoNewline
$fields = @(
    "frame.number",
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

# Helper function to normalize DNS ID
function Normalize-DnsId {
    param([string]$dnsId)
    if ([string]::IsNullOrWhiteSpace($dnsId)) { return "" }
    if ($dnsId -match "^0x") {
        return [int]::Parse($dnsId.Substring(2), [System.Globalization.NumberStyles]::AllowHexSpecifier).ToString()
    }
    return $dnsId
}

# Parse data
Write-Host "Parsing packets..." -NoNewline
$packets = New-Object System.Collections.ArrayList
foreach ($line in $rawData) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $fields = $line -split "`t"
    if ($fields.Count -lt 7) { continue }
    
    try {
        $dnsId = if ($fields[2]) { Normalize-DnsId $fields[2] } else { "" }
        $isResponse = if ($fields[5]) { $fields[5] -eq "True" -or $fields[5] -eq "1" } else { $false }
        
        $packet = [PSCustomObject]@{
            FrameNumber = if ($fields[0]) { [int]$fields[0] } else { 0 }
            TimeRelative = if ($fields[1]) { [double]$fields[1] } else { 0 }
            DnsId = $dnsId
            IpSource = if ($fields[3]) { $fields[3] } else { "" }
            IpDestination = if ($fields[4]) { $fields[4] } else { "" }
            IsResponse = $isResponse
            ResponseCode = if ($fields[6]) { $fields[6] } else { "0" }
            QueryName = if ($fields[7]) { $fields[7] } else { "" }
            QueryType = if ($fields[8]) { $fields[8] } else { "" }
        }
        [void]$packets.Add($packet)
    }
    catch { }
}
Write-Host " OK ($($packets.Count) packets)" -ForegroundColor Green

# Match requests with responses
Write-Host "Matching requests with responses..." -NoNewline
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

foreach ($request in $requests) {
    $requestCount++
    if ($requestCount % 5000 -eq 0) {
        Write-Host "." -NoNewline
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
Write-Host " OK ($($matchedQueries.Count) matched)" -ForegroundColor Green

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

# Top slow queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP $TopCount SLOWEST QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$topSlow = $matchedQueries | Sort-Object ResponseTimeMs -Descending | Select-Object -First $TopCount
$topSlow | ForEach-Object {
    $color = if ($_.ResponseTimeMs -gt 1000) { "Red" } elseif ($_.ResponseTimeMs -gt $SlowThresholdMs) { "Yellow" } else { "White" }
    Write-Host "$([math]::Round($_.ResponseTimeMs, 2)) ms | $($_.SourceIp) -> $($_.DnsServer) | $($_.QueryName) ($($_.QueryType))" -ForegroundColor $color
}

# Top sources by request count
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP $TopCount SOURCES (by request count)" -ForegroundColor Cyan
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
