# DNS Wireshark Trace Analysis - Detail Version
# Focus: <DOMAIN-FQDN> queries and internal domain performance

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
Write-Host "DNS Wireshark Analysis - Detail" -ForegroundColor Cyan
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
    Write-Host "Error: $rawData" -ForegroundColor Red
    exit 1
}
Write-Host " OK" -ForegroundColor Green

# Parse packets
Write-Host "Parsing packets..." -NoNewline
$packets = [System.Collections.Generic.List[object]]::new()
foreach ($line in $rawData) {
    if ($line -match '^\t') { continue }
    $fields = $line -split '\t'
    if ($fields.Count -ge 9) {
        try {
            $dnsId = if ($fields[2]) { $fields[2] } else { "" }
            $isResponse = $fields[5] -eq "1"
            
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

$matchedQueries = [System.Collections.Generic.List[object]]::new()
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
                IsInternal = ($request.IpDestination -eq "<IP-ADDRESS>" -or $request.IpDestination -eq "<IP-ADDRESS>")
            }
            [void]$matchedQueries.Add($matchedQuery)
        }
    }
}
Write-Host " OK ($($matchedQueries.Count) matched)" -ForegroundColor Green

# Export CSV
$csvPath = $PcapngFile -replace "\.pcapng$", "_Analysis.csv"
$matchedQueries | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "CSV exported to: $csvPath" -ForegroundColor Green
Write-Host ""

# Analyze <DOMAIN-FQDN> queries
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "<DOMAIN-FQDN> QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$domainQueries = $matchedQueries | Where-Object { $_.QueryName -match "<DOMAIN-FQDN>" -or $_.QueryName -match "<DOMAIN-FQDN>" -or $_.QueryName -match "<DOMAIN-NETBIOS>" }

if ($domainQueries.Count -eq 0) {
    Write-Host "No <DOMAIN-FQDN> queries found in trace!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Top domains queried:" -ForegroundColor Yellow
    $topDomains = $matchedQueries | Group-Object QueryName | Sort-Object Count -Descending | Select-Object -First 20
    $topDomains | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
}
else {
    Write-Host "Total <DOMAIN-FQDN> queries: $($domainQueries.Count)" -ForegroundColor White
    
    $stats = $domainQueries | Measure-Object -Property ResponseTimeMs -Average -Minimum -Maximum
    Write-Host "Average Response Time: $([math]::Round($stats.Average, 2)) ms" -ForegroundColor White
    Write-Host "Min Response Time: $([math]::Round($stats.Minimum, 2)) ms" -ForegroundColor White
    Write-Host "Max Response Time: $([math]::Round($stats.Maximum, 2)) ms" -ForegroundColor $(if ($stats.Maximum -gt 100) { "Red" } else { "White" })
    
    $slow = ($domainQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    Write-Host "Slow Queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Yellow" } else { "Green" })
    
    Write-Host ""
    Write-Host "<DOMAIN-FQDN> queries by type:" -ForegroundColor Yellow
    $byType = $domainQueries | Group-Object QueryType | Sort-Object Count -Descending
    $byType | ForEach-Object {
        $typeStats = $_.Group | Measure-Object -Property ResponseTimeMs -Average -Maximum
        Write-Host "  Type $($_.Name): $($_.Count) queries | Avg: $([math]::Round($typeStats.Average, 2))ms | Max: $([math]::Round($typeStats.Maximum, 2))ms" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Top 10 slowest <DOMAIN-FQDN> queries:" -ForegroundColor Yellow
    $topSlow = $domainQueries | Sort-Object ResponseTimeMs -Descending | Select-Object -First 10
    $topSlow | ForEach-Object {
        Write-Host "  $([math]::Round($_.ResponseTimeMs, 2))ms | $($_.SourceIp) -> $($_.DnsServer) | $($_.QueryName) (Type: $($_.QueryType))" -ForegroundColor $(if ($_.ResponseTimeMs -gt 100) { "Red" } else { "White" })
    }
}

# Internal vs External queries
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INTERNAL vs EXTERNAL QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$internalQueries = $matchedQueries | Where-Object { $_.IsInternal }
$externalQueries = $matchedQueries | Where-Object { -not $_.IsInternal }

Write-Host "Internal Queries (to <IP-ADDRESS>/12):" -ForegroundColor Yellow
$intStats = $internalQueries | Measure-Object -Property ResponseTimeMs -Average -Minimum -Maximum
Write-Host "  Count: $($internalQueries.Count)" -ForegroundColor White
Write-Host "  Avg: $([math]::Round($intStats.Average, 2))ms" -ForegroundColor White
Write-Host "  Min: $([math]::Round($intStats.Minimum, 2))ms" -ForegroundColor White
Write-Host "  Max: $([math]::Round($intStats.Maximum, 2))ms" -ForegroundColor White

Write-Host ""
Write-Host "External Queries (to other DNS servers):" -ForegroundColor Yellow
$extStats = $externalQueries | Measure-Object -Property ResponseTimeMs -Average -Minimum -Maximum
Write-Host "  Count: $($externalQueries.Count)" -ForegroundColor White
Write-Host "  Avg: $([math]::Round($extStats.Average, 2))ms" -ForegroundColor White
Write-Host "  Min: $([math]::Round($extStats.Minimum, 2))ms" -ForegroundColor White
Write-Host "  Max: $([math]::Round($extStats.Maximum, 2))ms" -ForegroundColor White

# Domain analysis
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DOMAIN ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Top 20 domains by query count:" -ForegroundColor Yellow
$domainStats = $matchedQueries | Group-Object QueryName | ForEach-Object {
    $queries = $_.Group
    $avgTime = ($queries | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxTime = ($queries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $slowCount = ($queries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
    
    [PSCustomObject]@{
        Domain = $_.Name
        QueryCount = $queries.Count
        AvgResponseTime = [math]::Round($avgTime, 2)
        MaxResponseTime = [math]::Round($maxTime, 2)
        SlowQueries = $slowCount
    }
} | Sort-Object QueryCount -Descending | Select-Object -First 20

$domainStats | Format-Table Domain, QueryCount, AvgResponseTime, MaxResponseTime, SlowQueries -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CSV file: $csvPath" -ForegroundColor Cyan
