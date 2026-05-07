# DNS Wireshark und Performance Counter Korrelation
# Korreliert Wireshark-Analyse-Daten mit Performance-Counter-Daten (logman)

param(
    [Parameter(Mandatory=$true)]
    [string]$WiresharkAnalysisCsv,
    [string]$PerformanceCounterPath = "\\<DC-SERVER>\c$\PerfLogs\DNS-Performance",
    [string]$Dc01Name = "<DC-SERVER>",
    [string]$Dc02Name = "<DC-SERVER>",
    [string]$OutputCsv = $null
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Wireshark / Performance Counter Korrelation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $WiresharkAnalysisCsv)) {
    Write-Host "ERROR: Wireshark Analysis CSV not found: $WiresharkAnalysisCsv" -ForegroundColor Red
    exit 1
}

# Read Wireshark Analysis Data
Write-Host "`nReading Wireshark Analysis Data..." -NoNewline
try {
    $wiresharkData = Import-Csv -Path $WiresharkAnalysisCsv -Encoding UTF8
    Write-Host " OK ($($wiresharkData.Count) queries)" -ForegroundColor Green
}
catch {
    Write-Host " ERROR" -ForegroundColor Red
    Write-Host "Failed to read Wireshark CSV: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Convert Wireshark timestamps to DateTime
Write-Host "Converting Wireshark timestamps..." -NoNewline
$wiresharkQueries = @()
foreach ($query in $wiresharkData) {
    try {
        # Try to parse as DateTime first (absolute timestamp)
        $timeRequest = $null
        $timeResponse = $null
        
        if ($query.TimeRequest -is [DateTime]) {
            $timeRequest = $query.TimeRequest
        }
        elseif ($query.TimeRequest -is [string]) {
            if ([DateTime]::TryParse($query.TimeRequest, [ref]$timeRequest)) {
                # Successfully parsed
            }
            else {
                # Try parsing as double (relative timestamp) - we'll need to use relative time
                if ([double]::TryParse($query.TimeRequest, [ref]$null)) {
                    # This is a relative timestamp, we can't correlate it without capture start time
                    Write-Warning "Query $($query.QueryName) has relative timestamp only - skipping correlation"
                    continue
                }
            }
        }
        else {
            $timeRequest = $query.TimeRequest
        }
        
        if ($query.TimeResponse -is [DateTime]) {
            $timeResponse = $query.TimeResponse
        }
        elseif ($query.TimeResponse -is [string]) {
            if (-not [DateTime]::TryParse($query.TimeResponse, [ref]$timeResponse)) {
                if ([double]::TryParse($query.TimeResponse, [ref]$null)) {
                    Write-Warning "Query $($query.QueryName) has relative timestamp only - skipping correlation"
                    continue
                }
            }
        }
        else {
            $timeResponse = $query.TimeResponse
        }
        
        if ($timeRequest -and $timeResponse) {
            $wiresharkQueries += [PSCustomObject]@{
                TimeRequest = $timeRequest
                TimeResponse = $timeResponse
                ResponseTimeMs = [double]$query.ResponseTimeMs
                QueryName = $query.QueryName
                QueryType = $query.QueryType
                DnsServer = $query.DnsServer
                ResponseCode = $query.ResponseCode
                Status = $query.Status
            }
        }
    }
    catch {
        Write-Warning "Failed to parse timestamp for query: $($query.QueryName) - $($_.Exception.Message)"
    }
}
Write-Host " OK ($($wiresharkQueries.Count) valid queries)" -ForegroundColor Green

# Find Performance Counter CSV files
Write-Host "`nSearching for Performance Counter CSV files..." -NoNewline
$perfFiles = @()

# Check DC01
$dc01Path = "\\$Dc01Name\c$\PerfLogs\DNS-Performance"
if (Test-Path $dc01Path) {
    $dc01Files = Get-ChildItem -Path $dc01Path -Filter "*.csv" | Sort-Object LastWriteTime -Descending
    if ($dc01Files.Count -gt 0) {
        $perfFiles += [PSCustomObject]@{
            Server = $Dc01Name
            Path = $dc01Files[0].FullName
            LastWriteTime = $dc01Files[0].LastWriteTime
        }
    }
}

# Check DC02
$dc02Path = "\\$Dc02Name\c$\PerfLogs\DNS-Performance"
if (Test-Path $dc02Path) {
    $dc02Files = Get-ChildItem -Path $dc02Path -Filter "*.csv" | Sort-Object LastWriteTime -Descending
    if ($dc02Files.Count -gt 0) {
        $perfFiles += [PSCustomObject]@{
            Server = $Dc02Name
            Path = $dc02Files[0].FullName
            LastWriteTime = $dc02Files[0].LastWriteTime
        }
    }
}

if ($perfFiles.Count -eq 0) {
    Write-Host " ERROR" -ForegroundColor Red
    Write-Host "No Performance Counter CSV files found!" -ForegroundColor Red
    Write-Host "Expected paths:" -ForegroundColor Yellow
    Write-Host "  $dc01Path" -ForegroundColor White
    Write-Host "  $dc02Path" -ForegroundColor White
    exit 1
}

Write-Host " OK (Found $($perfFiles.Count) files)" -ForegroundColor Green
foreach ($file in $perfFiles) {
    Write-Host "  $($file.Server): $($file.Path)" -ForegroundColor Cyan
}

# Read Performance Counter Data
Write-Host "`nReading Performance Counter Data..." -NoNewline
$perfData = @{}

foreach ($file in $perfFiles) {
    Write-Host "`n  Reading $($file.Server)..." -NoNewline
    try {
        $csvContent = Get-Content $file.Path
        $serverData = @()
        
        foreach ($line in ($csvContent | Select-Object -Skip 1)) {
            if ($line -match '^"([^"]+)","([^"]+)","([^"]+)","([^"]+)","([^"]+)","([^"]+)"') {
                try {
                    $timestampStr = $matches[1]
                    $totalReceived = [long]$matches[2]
                    $totalSent = [long]$matches[3]
                    $udpReceived = [long]$matches[4]
                    $tcpReceived = [long]$matches[5]
                    $recursive = [long]$matches[6]
                    
                    $timestamp = [DateTime]::ParseExact($timestampStr, "MM/dd/yyyy HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    
                    $serverData += [PSCustomObject]@{
                        Timestamp = $timestamp
                        TotalQueryReceived = $totalReceived
                        TotalResponseSent = $totalSent
                        UDPQueryReceived = $udpReceived
                        TCPQueryReceived = $tcpReceived
                        RecursiveQueries = $recursive
                    }
                }
                catch {
                    # Skip invalid rows
                }
            }
        }
        
        $perfData[$file.Server] = $serverData
        Write-Host " OK ($($serverData.Count) data points)" -ForegroundColor Green
    }
    catch {
        Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($perfData.Count -eq 0) {
    Write-Host "`nERROR: No Performance Counter data loaded!" -ForegroundColor Red
    exit 1
}

# Calculate query rates from Performance Counter data
Write-Host "`nCalculating query rates from Performance Counter data..." -NoNewline
$perfIntervals = @{}

foreach ($server in $perfData.Keys) {
    $intervals = @()
    $data = $perfData[$server]
    
    for ($i = 1; $i -lt $data.Count; $i++) {
        $timeDiff = ($data[$i].Timestamp - $data[$i-1].Timestamp).TotalSeconds
        $queryDiff = $data[$i].TotalQueryReceived - $data[$i-1].TotalQueryReceived
        
        if ($timeDiff -gt 0) {
            $queryRate = $queryDiff / $timeDiff
            
            $intervals += [PSCustomObject]@{
                Timestamp = $data[$i].Timestamp
                TimeDiffSeconds = $timeDiff
                QueryRate = [math]::Round($queryRate, 2)
                QueryCount = $queryDiff
                TotalQueryReceived = $data[$i].TotalQueryReceived
            }
        }
    }
    
    $perfIntervals[$server] = $intervals
}
Write-Host " OK" -ForegroundColor Green

# Correlate Wireshark queries with Performance Counter intervals
Write-Host "`nCorrelating Wireshark queries with Performance Counter data..." -NoNewline
$correlatedData = @()

foreach ($query in $wiresharkQueries) {
    $queryTime = $query.TimeRequest
    $dnsServer = $query.DnsServer
    
    # Determine which DC based on IP
    $targetServer = $null
    if ($dnsServer -match "10\.100\.10\.10") {
        $targetServer = $Dc01Name
    }
    elseif ($dnsServer -match "10\.100\.10\.12") {
        $targetServer = $Dc02Name
    }
    
    if ($targetServer -and $perfIntervals.ContainsKey($targetServer)) {
        # Find closest Performance Counter interval
        $closestInterval = $perfIntervals[$targetServer] | 
            Where-Object { [math]::Abs(($_.Timestamp - $queryTime).TotalSeconds) -lt 30 } |
            Sort-Object { [math]::Abs(($_.Timestamp - $queryTime).TotalSeconds) } |
            Select-Object -First 1
        
        if ($closestInterval) {
            $correlatedData += [PSCustomObject]@{
                QueryTime = $queryTime
                ResponseTimeMs = $query.ResponseTimeMs
                QueryName = $query.QueryName
                QueryType = $query.QueryType
                DnsServer = $dnsServer
                TargetServer = $targetServer
                PerfCounterTime = $closestInterval.Timestamp
                TimeDiffSeconds = [math]::Round(($closestInterval.Timestamp - $queryTime).TotalSeconds, 1)
                QueryRate = $closestInterval.QueryRate
                QueryCountInInterval = $closestInterval.QueryCount
                TotalQueriesOnServer = $closestInterval.TotalQueryReceived
                ResponseCode = $query.ResponseCode
                Status = $query.Status
            }
        }
    }
}

Write-Host " OK ($($correlatedData.Count) queries correlated)" -ForegroundColor Green

# Analysis
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CORRELATION ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($correlatedData.Count -eq 0) {
    Write-Host "`nWARNING: No queries could be correlated!" -ForegroundColor Yellow
    Write-Host "This could mean:" -ForegroundColor Yellow
    Write-Host "  - Wireshark capture time does not overlap with Performance Counter data" -ForegroundColor White
    Write-Host "  - DNS server IPs in Wireshark data don't match expected DCs" -ForegroundColor White
    Write-Host "  - Performance Counter data is not available for the capture period" -ForegroundColor White
    exit 0
}

# Time range
$minTime = ($correlatedData | Measure-Object -Property QueryTime -Minimum).Minimum
$maxTime = ($correlatedData | Measure-Object -Property QueryTime -Maximum).Maximum
Write-Host "`nTime Range:" -ForegroundColor Yellow
Write-Host "  Start: $minTime" -ForegroundColor White
Write-Host "  End: $maxTime" -ForegroundColor White
Write-Host "  Duration: $([math]::Round(($maxTime - $minTime).TotalMinutes, 1)) minutes" -ForegroundColor White

# Response Time vs Query Rate correlation
Write-Host "`nResponse Time vs Query Rate Correlation:" -ForegroundColor Yellow
$avgResponseTime = ($correlatedData | Measure-Object -Property ResponseTimeMs -Average).Average
$avgQueryRate = ($correlatedData | Measure-Object -Property QueryRate -Average).Average
Write-Host "  Average Response Time: $([math]::Round($avgResponseTime, 2)) ms" -ForegroundColor White
Write-Host "  Average Query Rate: $([math]::Round($avgQueryRate, 2)) queries/sec" -ForegroundColor White

# Group by Query Rate ranges
Write-Host "`nResponse Times by Query Rate:" -ForegroundColor Yellow
$rateGroups = $correlatedData | Group-Object { 
    if ($_.QueryRate -lt 10) { "Low (<10/sec)" }
    elseif ($_.QueryRate -lt 50) { "Medium (10-50/sec)" }
    elseif ($_.QueryRate -lt 100) { "High (50-100/sec)" }
    else { "Very High (>100/sec)" }
}

foreach ($group in $rateGroups) {
    $avgResponse = ($group.Group | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxResponse = ($group.Group | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $count = $group.Count
    
    $color = if ($avgResponse -gt 100) { "Red" } elseif ($avgResponse -gt 50) { "Yellow" } else { "Green" }
    Write-Host "  $($group.Name):" -ForegroundColor $color
    Write-Host "    Queries: $count" -ForegroundColor White
    Write-Host "    Avg Response Time: $([math]::Round($avgResponse, 2)) ms" -ForegroundColor White
    Write-Host "    Max Response Time: $([math]::Round($maxResponse, 2)) ms" -ForegroundColor White
}

# Server comparison
Write-Host "`nServer Comparison:" -ForegroundColor Yellow
$serverGroups = $correlatedData | Group-Object TargetServer
foreach ($group in $serverGroups) {
    $avgResponse = ($group.Group | Measure-Object -Property ResponseTimeMs -Average).Average
    $maxResponse = ($group.Group | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    $avgRate = ($group.Group | Measure-Object -Property QueryRate -Average).Average
    
    $color = if ($avgResponse -gt 100) { "Red" } elseif ($avgResponse -gt 50) { "Yellow" } else { "Green" }
    Write-Host "  $($group.Name):" -ForegroundColor $color
    Write-Host "    Queries: $($group.Count)" -ForegroundColor White
    Write-Host "    Avg Response Time: $([math]::Round($avgResponse, 2)) ms" -ForegroundColor White
    Write-Host "    Max Response Time: $([math]::Round($maxResponse, 2)) ms" -ForegroundColor White
    Write-Host "    Avg Query Rate: $([math]::Round($avgRate, 2)) queries/sec" -ForegroundColor White
}

# Peak load analysis
Write-Host "`nPeak Load Analysis:" -ForegroundColor Yellow
$peakQueries = $correlatedData | Where-Object { $_.QueryRate -gt 50 } | Sort-Object QueryRate -Descending
if ($peakQueries.Count -gt 0) {
    Write-Host "  Found $($peakQueries.Count) queries during high load (>50 queries/sec)" -ForegroundColor $(if ($peakQueries.Count -gt 10) { "Red" } else { "Yellow" })
    $peakAvgResponse = ($peakQueries | Measure-Object -Property ResponseTimeMs -Average).Average
    $peakMaxResponse = ($peakQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
    Write-Host "    Avg Response Time during peaks: $([math]::Round($peakAvgResponse, 2)) ms" -ForegroundColor White
    Write-Host "    Max Response Time during peaks: $([math]::Round($peakMaxResponse, 2)) ms" -ForegroundColor White
    
    Write-Host "`n  Top 10 queries during peak load:" -ForegroundColor Cyan
    $peakQueries | Select-Object -First 10 | ForEach-Object {
        Write-Host "    $([math]::Round($_.ResponseTimeMs, 2)) ms @ $([math]::Round($_.QueryRate, 1)) queries/sec - $($_.QueryName) -> $($_.DnsServer)" -ForegroundColor White
    }
}
else {
    Write-Host "  No queries during high load periods" -ForegroundColor Green
}

# Export correlated data
if ($OutputCsv) {
    Write-Host "`nExporting correlated data to CSV..." -NoNewline
    $correlatedData | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Host " OK" -ForegroundColor Green
    Write-Host "  File: $OutputCsv" -ForegroundColor Cyan
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Correlation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

$correlatedData
