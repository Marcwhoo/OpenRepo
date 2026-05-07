# DNS Wireshark Trace Analysis
# Analyzes pcapng files and extracts DNS response times

param(
    [Parameter(Mandatory=$true)]
    [string]$PcapngFile,
    [string]$OutputCsv = $null
)

$tsharkPath = "C:\Program Files\Wireshark\tshark.exe"

if (-not (Test-Path $tsharkPath)) {
    Write-Host "ERROR: tshark.exe not found at $tsharkPath" -ForegroundColor Red
    Write-Host "Please ensure Wireshark is installed." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $PcapngFile)) {
    Write-Host "ERROR: pcapng file not found: $PcapngFile" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Wireshark Trace Analysis" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "File: $PcapngFile" -ForegroundColor Yellow
Write-Host ""

# Extract DNS packets with all relevant fields
Write-Host "Extracting DNS packets..." -NoNewline
$fields = @(
    "frame.number",
    "frame.time",
    "frame.time_relative",
    "frame.time_delta",
    "dns.id",
    "ip.src",
    "ip.dst",
    "dns.flags.response",
    "dns.flags.rcode",
    "dns.qry.name",
    "dns.qry.type",
    "dns.resp.type",
    "dns.count.queries",
    "dns.count.answers",
    "dns.flags.recdesired",
    "dns.flags.recavail",
    "udp.length",
    "tcp.len"
)

$tsharkArgs = @("-r", $PcapngFile, "-Y", "dns", "-T", "fields")
foreach ($field in $fields) {
    $tsharkArgs += "-e"
    $tsharkArgs += $field
}

try {
    $rawData = & $tsharkPath $tsharkArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host " ERROR" -ForegroundColor Red
        Write-Host "Failed to extract data: $rawData" -ForegroundColor Red
        exit 1
    }
    
    Write-Host " OK" -ForegroundColor Green
}
catch {
    Write-Host " ERROR" -ForegroundColor Red
    Write-Host "Failed to extract data: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

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
Write-Host "Parsing DNS packets..." -NoNewline
$packets = New-Object System.Collections.ArrayList
$lineCount = 0

foreach ($line in $rawData) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    
    $fields = $line -split "`t"
    if ($fields.Count -lt 10) { continue }
    
    $lineCount++
    if ($lineCount % 5000 -eq 0) {
        Write-Host "." -NoNewline
    }
    
    try {
        $frameNum = if ($fields[0]) { [int]$fields[0] } else { 0 }
        $timeAbs = if ($fields[1]) { $fields[1] } else { "" }
        $timeRel = if ($fields[2]) { [double]$fields[2] } else { 0 }
        $timeDelta = if ($fields[3]) { [double]$fields[3] } else { 0 }
        $dnsId = if ($fields[4]) { Normalize-DnsId $fields[4] } else { "" }
        $ipSrc = if ($fields[5]) { $fields[5] } else { "" }
        $ipDst = if ($fields[6]) { $fields[6] } else { "" }
        $isResponse = if ($fields[7]) { $fields[7] -eq "True" -or $fields[7] -eq "1" } else { $false }
        $rcode = if ($fields[8]) { $fields[8] } else { "0" }
        $qryName = if ($fields[9]) { $fields[9] } else { "" }
        $qryType = if ($fields[10]) { $fields[10] } else { "" }
        $respType = if ($fields[11]) { $fields[11] } else { "" }
        $countQueries = if ($fields[12]) { [int]$fields[12] } else { 0 }
        $countAnswers = if ($fields[13]) { [int]$fields[13] } else { 0 }
        $recDesired = if ($fields[14]) { $fields[14] -eq "True" -or $fields[14] -eq "1" } else { $false }
        $recAvail = if ($fields[15]) { $fields[15] -eq "True" -or $fields[15] -eq "1" } else { $false }
        $udpLen = if ($fields[16]) { [int]$fields[16] } else { 0 }
        $tcpLen = if ($fields[17]) { [int]$fields[17] } else { 0 }
        
        # Parse absolute timestamp
        $timeAbsolute = $null
        if ($timeAbs) {
            try {
                $timeAbsolute = [DateTime]::Parse($timeAbs)
            }
            catch {
                # Try alternative format
                try {
                    $timeAbsolute = [DateTime]::ParseExact($timeAbs, "MMM dd, yyyy HH:mm:ss.ffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                }
                catch {
                    # If parsing fails, keep as string
                }
            }
        }
        
        $packet = [PSCustomObject]@{
            FrameNumber = $frameNum
            TimeAbsolute = $timeAbsolute
            TimeAbsoluteString = $timeAbs
            TimeRelative = $timeRel
            TimeDelta = $timeDelta
            DnsId = $dnsId
            IpSource = $ipSrc
            IpDestination = $ipDst
            IsResponse = $isResponse
            ResponseCode = $rcode
            QueryName = $qryName
            QueryType = $qryType
            ResponseType = $respType
            CountQueries = $countQueries
            CountAnswers = $countAnswers
            RecursionDesired = $recDesired
            RecursionAvailable = $recAvail
            PacketSize = if ($udpLen -gt 0) { $udpLen } else { $tcpLen }
        }
        
        [void]$packets.Add($packet)
    }
    catch {
        Write-Warning "Failed to parse line $lineCount : $_"
    }
}

Write-Host " OK ($($packets.Count) packets)" -ForegroundColor Green

# Match requests with responses
Write-Host "Matching requests with responses..." -NoNewline
$requests = $packets | Where-Object { -not $_.IsResponse }
$responses = $packets | Where-Object { $_.IsResponse }

# Build response index for fast lookup
$responseIndex = @{}
foreach ($response in $responses) {
    if ([string]::IsNullOrWhiteSpace($response.DnsId)) { continue }
    $key = "$($response.DnsId)|$($response.IpSource)|$($response.IpDestination)"
    if (-not $responseIndex.ContainsKey($key)) {
        $responseIndex[$key] = @()
    }
    $responseIndex[$key] += $response
}

# Sort responses by time for each key
foreach ($key in $responseIndex.Keys) {
    $responseIndex[$key] = $responseIndex[$key] | Sort-Object TimeRelative
}

$matchedQueries = New-Object System.Collections.ArrayList
$unmatchedRequests = New-Object System.Collections.ArrayList
$requestCount = 0
$totalRequests = $requests.Count

foreach ($request in $requests) {
    $requestCount++
    if ($requestCount % 1000 -eq 0) {
        Write-Host "." -NoNewline
    }
    
    if ([string]::IsNullOrWhiteSpace($request.DnsId)) { continue }
    
    # Build lookup key (reversed IPs for response)
    $lookupKey = "$($request.DnsId)|$($request.IpDestination)|$($request.IpSource)"
    
    if ($responseIndex.ContainsKey($lookupKey)) {
        # Find first response after request time
        $matchingResponse = $responseIndex[$lookupKey] | Where-Object { $_.TimeRelative -gt $request.TimeRelative } | Select-Object -First 1
        
        if ($matchingResponse) {
            $responseTime = ($matchingResponse.TimeRelative - $request.TimeRelative) * 1000
            $matchedQuery = [PSCustomObject]@{
                FrameNumberRequest = $request.FrameNumber
                FrameNumberResponse = $matchingResponse.FrameNumber
                TimeRequest = if ($request.TimeAbsolute) { $request.TimeAbsolute } else { $request.TimeRelative }
                TimeResponse = if ($matchingResponse.TimeAbsolute) { $matchingResponse.TimeAbsolute } else { $matchingResponse.TimeRelative }
                TimeRequestRelative = $request.TimeRelative
                TimeResponseRelative = $matchingResponse.TimeRelative
                ResponseTimeMs = [math]::Round($responseTime, 3)
                DnsId = $request.DnsId
                QueryName = $request.QueryName
                QueryType = $request.QueryType
                ResponseType = $matchingResponse.ResponseType
                ResponseCode = $matchingResponse.ResponseCode
                CountAnswers = $matchingResponse.CountAnswers
                IpSource = $request.IpSource
                DnsServer = $request.IpDestination
                RecursionDesired = $request.RecursionDesired
                RecursionAvailable = $matchingResponse.RecursionAvailable
                PacketSizeRequest = $request.PacketSize
                PacketSizeResponse = $matchingResponse.PacketSize
                Status = if ($matchingResponse.ResponseCode -eq "0") { "Success" } else { "Error_$($matchingResponse.ResponseCode)" }
            }
            [void]$matchedQueries.Add($matchedQuery)
        }
        else {
            [void]$unmatchedRequests.Add($request)
        }
    }
    else {
        [void]$unmatchedRequests.Add($request)
    }
}

Write-Host " OK ($($matchedQueries.Count) matched, $($unmatchedRequests.Count) unmatched)" -ForegroundColor Green

# Analysis
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ANALYSIS RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($matchedQueries.Count -eq 0) {
    Write-Host "`nWARNING: No matched DNS queries found!" -ForegroundColor Yellow
    Write-Host "This could indicate:" -ForegroundColor Yellow
    Write-Host "  - All queries timed out" -ForegroundColor Yellow
    Write-Host "  - Responses are missing in capture" -ForegroundColor Yellow
    Write-Host "  - DNS ID matching failed" -ForegroundColor Yellow
    exit 0
}

# Response Time Statistics
Write-Host "`nResponse Time Statistics:" -ForegroundColor Yellow
$avgResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Average).Average
$minResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
$maxResponseTime = ($matchedQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
$medianResponseTime = ($matchedQueries | Sort-Object ResponseTimeMs)[[math]::Floor($matchedQueries.Count / 2)].ResponseTimeMs
$p95ResponseTime = ($matchedQueries | Sort-Object ResponseTimeMs)[[math]::Floor($matchedQueries.Count * 0.95)].ResponseTimeMs
$p99ResponseTime = ($matchedQueries | Sort-Object ResponseTimeMs)[[math]::Floor($matchedQueries.Count * 0.99)].ResponseTimeMs

Write-Host "  Total Queries: $($matchedQueries.Count)" -ForegroundColor White
Write-Host "  Average: $([math]::Round($avgResponseTime, 2)) ms" -ForegroundColor White
Write-Host "  Minimum: $([math]::Round($minResponseTime, 2)) ms" -ForegroundColor White
Write-Host "  Maximum: $([math]::Round($maxResponseTime, 2)) ms" -ForegroundColor $(if ($maxResponseTime -gt 1000) { "Red" } else { "White" })
Write-Host "  Median: $([math]::Round($medianResponseTime, 2)) ms" -ForegroundColor White
Write-Host "  95th Percentile: $([math]::Round($p95ResponseTime, 2)) ms" -ForegroundColor White
Write-Host "  99th Percentile: $([math]::Round($p99ResponseTime, 2)) ms" -ForegroundColor White

# Slow queries
Write-Host "`nSlow Queries (>100ms):" -ForegroundColor Yellow
$slowQueries = $matchedQueries | Where-Object { $_.ResponseTimeMs -gt 100 } | Sort-Object ResponseTimeMs -Descending
if ($slowQueries.Count -gt 0) {
    Write-Host "  Found $($slowQueries.Count) slow queries" -ForegroundColor $(if ($slowQueries.Count -gt 10) { "Red" } else { "Yellow" })
    $slowQueries | Select-Object -First 10 | ForEach-Object {
        Write-Host "    $($_.ResponseTimeMs) ms - $($_.QueryName) ($($_.QueryType)) -> $($_.DnsServer)" -ForegroundColor White
    }
}
else {
    Write-Host "  None found" -ForegroundColor Green
}

# Very slow queries
Write-Host "`nVery Slow Queries (>1000ms):" -ForegroundColor Yellow
$verySlowQueries = $matchedQueries | Where-Object { $_.ResponseTimeMs -gt 1000 } | Sort-Object ResponseTimeMs -Descending
if ($verySlowQueries.Count -gt 0) {
    Write-Host "  Found $($verySlowQueries.Count) very slow queries" -ForegroundColor Red
    $verySlowQueries | Select-Object -First 10 | ForEach-Object {
        Write-Host "    $($_.ResponseTimeMs) ms - $($_.QueryName) ($($_.QueryType)) -> $($_.DnsServer)" -ForegroundColor Red
    }
}
else {
    Write-Host "  None found" -ForegroundColor Green
}

# DNS Server Statistics
Write-Host "`nDNS Server Statistics:" -ForegroundColor Yellow
$serverStats = $matchedQueries | Group-Object DnsServer | ForEach-Object {
    $server = $_.Name
    $queries = $_.Group
    $avgTime = ($queries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($queries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $minTime = ($queries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
    
    [PSCustomObject]@{
        DnsServer = $server
        QueryCount = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MinResponseTime = [math]::Round($minTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
    }
} | Sort-Object AvgResponseTime -Descending

$serverStats | ForEach-Object {
    $color = if ($_.AvgResponseTime -gt 100) { "Red" } elseif ($_.AvgResponseTime -gt 50) { "Yellow" } else { "Green" }
    Write-Host "  $($_.DnsServer):" -ForegroundColor $color
    Write-Host "    Queries: $($_.QueryCount)" -ForegroundColor White
    Write-Host "    Avg: $($_.AvgResponseTime) ms" -ForegroundColor White
    Write-Host "    Min: $($_.MinResponseTime) ms, Max: $($_.MaxResponseTime) ms" -ForegroundColor White
}

# Query Type Statistics
Write-Host "`nQuery Type Statistics:" -ForegroundColor Yellow
$typeStats = $matchedQueries | Group-Object QueryType | ForEach-Object {
    $type = if ($_.Name) { $_.Name } else { "Unknown" }
    $queries = $_.Group
    $avgTime = ($queries | Measure-Object -Property ResponseTimeMs -Average).Average
    
    [PSCustomObject]@{
        QueryType = $type
        QueryCount = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
    }
} | Sort-Object QueryCount -Descending

$typeStats | ForEach-Object {
    Write-Host "  $($_.QueryType): $($_.QueryCount) queries, Avg: $($_.AvgResponseTime) ms" -ForegroundColor White
}

# Error Statistics
Write-Host "`nError Statistics:" -ForegroundColor Yellow
$errorQueries = $matchedQueries | Where-Object { $_.ResponseCode -ne "0" }
if ($errorQueries.Count -gt 0) {
    Write-Host "  Found $($errorQueries.Count) queries with errors" -ForegroundColor Red
    $errorQueries | Group-Object ResponseCode | ForEach-Object {
        Write-Host "    Error Code $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
}
else {
    Write-Host "  No errors found" -ForegroundColor Green
}

# Unmatched Requests
if ($unmatchedRequests.Count -gt 0) {
    Write-Host "`nUnmatched Requests (no response found):" -ForegroundColor Yellow
    Write-Host "  Found $($unmatchedRequests.Count) requests without matching response" -ForegroundColor $(if ($unmatchedRequests.Count -gt 10) { "Red" } else { "Yellow" })
    $unmatchedRequests | Select-Object -First 10 | ForEach-Object {
        Write-Host "    $($_.QueryName) ($($_.QueryType)) -> $($_.IpDestination)" -ForegroundColor White
    }
}

# Export to CSV
if ($OutputCsv) {
    Write-Host "`nExporting to CSV..." -NoNewline
    $matchedQueries | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Host " OK" -ForegroundColor Green
    Write-Host "  File: $OutputCsv" -ForegroundColor Cyan
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

$matchedQueries
