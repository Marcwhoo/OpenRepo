# DNS SOA Query Analysis from Wireshark Trace
# Extracts and analyzes SOA queries (Type 6) directly from pcapng file

param(
    [Parameter(Mandatory=$true)]
    [string]$PcapngFile
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
Write-Host "DNS SOA Query Analysis (Wireshark)" -ForegroundColor Cyan
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
        $queryType = if ($fields[8]) { $fields[8] } else { "" }
        
        # Only process SOA queries (Type 6)
        if ($queryType -ne "6") { continue }
        
        $packet = [PSCustomObject]@{
            FrameNumber = if ($fields[0]) { [int]$fields[0] } else { 0 }
            TimeRelative = if ($fields[1]) { [double]$fields[1] } else { 0 }
            DnsId = $dnsId
            IpSource = if ($fields[3]) { $fields[3] } else { "" }
            IpDestination = if ($fields[4]) { $fields[4] } else { "" }
            IsResponse = $isResponse
            ResponseCode = if ($fields[6]) { $fields[6] } else { "0" }
            QueryName = if ($fields[7]) { $fields[7] } else { "" }
            QueryType = $queryType
        }
        [void]$packets.Add($packet)
    }
    catch { }
}
Write-Host " OK ($($packets.Count) SOA packets)" -ForegroundColor Green

# Match requests with responses
Write-Host "Matching SOA requests with responses..." -NoNewline
$requests = $packets | Where-Object { -not $_.IsResponse }
$responses = $packets | Where-Object { $_.IsResponse }

Write-Host " (Requests: $($requests.Count), Responses: $($responses.Count))" -NoNewline

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
    if ($requestCount % 100 -eq 0) {
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
Write-Host "SOA QUERY SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($matchedQueries.Count -eq 0) {
    Write-Host "No matched SOA queries found!" -ForegroundColor Yellow
    Write-Host "Total SOA requests: $($requests.Count)" -ForegroundColor White
    Write-Host "Total SOA responses: $($responses.Count)" -ForegroundColor White
    Write-Host ""
    Write-Host "Note: Unmatched queries may be:" -ForegroundColor Yellow
    Write-Host "  - Responses without requests (forwarded queries)" -ForegroundColor Gray
    Write-Host "  - Requests without responses (timeouts)" -ForegroundColor Gray
    Write-Host "  - Different DNS IDs or IP addresses" -ForegroundColor Gray
    exit 0
}

$totalQueries = $matchedQueries.Count
$avgResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$maxResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$minResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
$slowQueries = ($matchedQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

Write-Host "Total SOA Queries: $totalQueries" -ForegroundColor White
Write-Host "Average Response Time: $([math]::Round($avgResponseTime, 2)) ms" -ForegroundColor $(if ($avgResponseTime -gt 50) { "Red" } elseif ($avgResponseTime -gt 10) { "Yellow" } else { "Green" })
Write-Host "Min Response Time: $([math]::Round($minResponseTime, 2)) ms" -ForegroundColor White
Write-Host "Max Response Time: $([math]::Round($maxResponseTime, 2)) ms" -ForegroundColor $(if ($maxResponseTime -gt 100) { "Red" } else { "White" })
Write-Host "Slow Queries (>100ms): $slowQueries" -ForegroundColor $(if ($slowQueries -gt 0) { "Red" } else { "Green" })

# SOA queries by domain
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY DOMAIN" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaByDomain = $matchedQueries | Where-Object { $_.QueryName -ne "" } | Group-Object QueryName | ForEach-Object {
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

if ($soaByDomain.Count -gt 0) {
    $soaByDomain | Format-Table Domain, QueryCount, AvgResponseTimeMs, MinResponseTimeMs, MaxResponseTimeMs, IsInternal -AutoSize
} else {
    Write-Host "No domain-specific SOA queries found" -ForegroundColor Yellow
}

# Slow SOA queries detail
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SLOW SOA QUERIES (>100ms)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$slowSoaQueries = $matchedQueries | Where-Object { $_.ResponseTimeMs -gt 100 } | Sort-Object ResponseTimeMs -Descending

if ($slowSoaQueries.Count -gt 0) {
    Write-Host "Found $($slowSoaQueries.Count) slow SOA queries:" -ForegroundColor Yellow
    $slowSoaQueries | Select-Object -First 20 | Format-Table ResponseTimeMs, QueryName, SourceIp, DnsServer, ResponseCode -AutoSize
} else {
    Write-Host "No slow SOA queries found (>100ms)" -ForegroundColor Green
}

# SOA queries by source
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY SOURCE IP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaBySource = $matchedQueries | Group-Object SourceIp | ForEach-Object {
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

if ($soaBySource.Count -gt 0) {
    $soaBySource | Format-Table SourceIp, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
} else {
    Write-Host "No source-specific SOA queries found" -ForegroundColor Yellow
}

# SOA queries by DNS server
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERIES BY DNS SERVER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$soaByServer = $matchedQueries | Group-Object DnsServer | ForEach-Object {
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

if ($soaByServer.Count -gt 0) {
    $soaByServer | Format-Table DnsServer, QueryCount, AvgResponseTimeMs, MaxResponseTimeMs -AutoSize
} else {
    Write-Host "No server-specific SOA queries found" -ForegroundColor Yellow
}

# Response time distribution for SOA
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SOA QUERY RESPONSE TIME DISTRIBUTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$fast = ($matchedQueries | Where-Object { $_.ResponseTimeMs -le 10 }).Count
$normal = ($matchedQueries | Where-Object { $_.ResponseTimeMs -gt 10 -and $_.ResponseTimeMs -le 50 }).Count
$slow = ($matchedQueries | Where-Object { $_.ResponseTimeMs -gt 50 -and $_.ResponseTimeMs -le 100 }).Count
$verySlow = ($matchedQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count

$total = $matchedQueries.Count
Write-Host "<= 10ms:   $fast ($([math]::Round(($fast / $total) * 100, 2))%)" -ForegroundColor Green
Write-Host "10-50ms:   $normal ($([math]::Round(($normal / $total) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "50-100ms:  $slow ($([math]::Round(($slow / $total) * 100, 2))%)" -ForegroundColor Yellow
Write-Host "> 100ms:   $verySlow ($([math]::Round(($verySlow / $total) * 100, 2))%)" -ForegroundColor Red

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
