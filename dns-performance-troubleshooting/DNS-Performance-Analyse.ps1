# DNS Performance Log Analysis
# Analyzes DNS performance counter CSV files

param(
    [string]$CsvPath = ".\DNS-Performance_01230800.csv"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Performance Log Analysis" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $CsvPath)) {
    Write-Host "ERROR: CSV file not found: $CsvPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nReading CSV file..." -ForegroundColor Yellow
$data = [System.Collections.Generic.List[object]]::new()
$lineCount = 0
$regex = [regex]'^"([^"]+)","([^"]+)","([^"]+)","([^"]+)","([^"]+)","([^"]+)"'

$reader = [System.IO.StreamReader]::new($CsvPath)
$null = $reader.ReadLine()
$fileSize = (Get-Item $CsvPath).Length

while ($null -ne ($line = $reader.ReadLine())) {
    $lineCount++
    if ($lineCount % 5000 -eq 0) {
        $percent = [math]::Round(($reader.BaseStream.Position / $fileSize) * 100, 1)
        Write-Progress -Activity "Reading CSV" -Status "Processing line $lineCount ($percent%)" -PercentComplete $percent
    }
    
    $match = $regex.Match($line)
    if ($match.Success) {
        try {
            $timestampStr = $match.Groups[1].Value
            $totalReceived = [long]$match.Groups[2].Value
            $totalSent = [long]$match.Groups[3].Value
            $udpReceived = [long]$match.Groups[4].Value
            $tcpReceived = [long]$match.Groups[5].Value
            $recursive = [long]$match.Groups[6].Value
            
            $timestamp = [DateTime]::ParseExact($timestampStr, "MM/dd/yyyy HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
        
            $data.Add([PSCustomObject]@{
                Timestamp = $timestamp
                TotalQueryReceived = $totalReceived
                TotalResponseSent = $totalSent
                UDPQueryReceived = $udpReceived
                TCPQueryReceived = $tcpReceived
                RecursiveQueries = $recursive
            })
        }
        catch {
            Write-Warning "Skipping invalid row: $timestampStr"
        }
    }
}
$reader.Close()
Write-Progress -Activity "Reading CSV" -Completed

if ($data.Count -eq 0) {
    Write-Host "ERROR: No valid data found in CSV" -ForegroundColor Red
    exit 1
}

Write-Host "OK ($($data.Count) data points)" -ForegroundColor Green

# Calculate differences (queries per interval)
Write-Host "`nCalculating query rates..." -ForegroundColor Yellow
$intervals = [System.Collections.Generic.List[object]]::new()
$totalIntervals = $data.Count - 1

for ($i = 1; $i -lt $data.Count; $i++) {
    if ($i % 5000 -eq 0) {
        $percent = [math]::Round(($i / $totalIntervals) * 100, 1)
        Write-Progress -Activity "Calculating intervals" -Status "Processing interval $i of $totalIntervals ($percent%)" -PercentComplete $percent
    }
    
    $timeDiff = ($data[$i].Timestamp - $data[$i-1].Timestamp).TotalSeconds
    if ($timeDiff -gt 0) {
        $queryDiff = $data[$i].TotalQueryReceived - $data[$i-1].TotalQueryReceived
        $responseDiff = $data[$i].TotalResponseSent - $data[$i-1].TotalResponseSent
        $udpDiff = $data[$i].UDPQueryReceived - $data[$i-1].UDPQueryReceived
        $tcpDiff = $data[$i].TCPQueryReceived - $data[$i-1].TCPQueryReceived
        $recursiveDiff = $data[$i].RecursiveQueries - $data[$i-1].RecursiveQueries
        
        $invTimeDiff = 1.0 / $timeDiff
        $intervals.Add([PSCustomObject]@{
            Timestamp = $data[$i].Timestamp
            TimeDiffSeconds = $timeDiff
            QueryRate = [math]::Round($queryDiff * $invTimeDiff, 2)
            ResponseRate = [math]::Round($responseDiff * $invTimeDiff, 2)
            UDPRate = [math]::Round($udpDiff * $invTimeDiff, 2)
            TCPRate = [math]::Round($tcpDiff * $invTimeDiff, 2)
            RecursiveRate = [math]::Round($recursiveDiff * $invTimeDiff, 2)
            QueryCount = $queryDiff
            ResponseCount = $responseDiff
        })
    }
}
Write-Progress -Activity "Calculating intervals" -Completed

# Analysis
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ANALYSIS RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTime Period:" -ForegroundColor Yellow
Write-Host "  Start: $($data[0].Timestamp)" -ForegroundColor White
Write-Host "  End: $($data[-1].Timestamp)" -ForegroundColor White
$duration = ($data[-1].Timestamp - $data[0].Timestamp).TotalMinutes
Write-Host "  Duration: $([math]::Round($duration, 2)) minutes" -ForegroundColor White

Write-Host "`nQuery Rate Statistics:" -ForegroundColor Yellow
$stats = $intervals | Measure-Object -Property QueryRate -Average -Minimum -Maximum
Write-Host "  Average: $([math]::Round($stats.Average, 2)) queries/sec" -ForegroundColor White
Write-Host "  Minimum: $([math]::Round($stats.Minimum, 2)) queries/sec" -ForegroundColor White
Write-Host "  Maximum: $([math]::Round($stats.Maximum, 2)) queries/sec" -ForegroundColor $(if ($stats.Maximum -gt 100) { "Red" } else { "White" })

Write-Host "`nPeak Load Intervals (> 50 queries/sec):" -ForegroundColor Yellow
$peaks = $intervals | Where-Object { $_.QueryRate -gt 50 } | Sort-Object QueryRate -Descending | Select-Object -First 10
if ($peaks.Count -gt 0) {
    foreach ($peak in $peaks) {
        Write-Host "  $($peak.Timestamp): $($peak.QueryRate) queries/sec ($($peak.QueryCount) queries in $([math]::Round($peak.TimeDiffSeconds, 1))s)" -ForegroundColor $(if ($peak.QueryRate -gt 100) { "Red" } else { "Yellow" })
    }
}
else {
    Write-Host "  No peaks above 50 queries/sec" -ForegroundColor Green
}

Write-Host "`nProtocol Distribution:" -ForegroundColor Yellow
$totalUDP = ($intervals | Measure-Object -Property UDPRate -Sum).Sum
$totalTCP = ($intervals | Measure-Object -Property TCPRate -Sum).Sum
$totalQueries = $totalUDP + $totalTCP
if ($totalQueries -gt 0) {
    $udpPercent = [math]::Round(($totalUDP / $totalQueries) * 100, 1)
    $tcpPercent = [math]::Round(($totalTCP / $totalQueries) * 100, 1)
    Write-Host "  UDP: $udpPercent% ($([math]::Round($totalUDP, 0)) queries)" -ForegroundColor White
    Write-Host "  TCP: $tcpPercent% ($([math]::Round($totalTCP, 0)) queries)" -ForegroundColor White
}

Write-Host "`nRecursive Query Rate:" -ForegroundColor Yellow
$avgRecursive = ($intervals | Measure-Object -Property RecursiveRate -Average).Average
$totalRecursive = ($intervals | Measure-Object -Property RecursiveRate -Sum).Sum
$totalAll = ($intervals | Measure-Object -Property QueryRate -Sum).Sum
if ($totalAll -gt 0) {
    $recursivePercent = [math]::Round(($totalRecursive / $totalAll) * 100, 1)
    Write-Host "  Average: $([math]::Round($avgRecursive, 2)) recursive queries/sec" -ForegroundColor White
    Write-Host "  Percentage: $recursivePercent% of all queries" -ForegroundColor White
}

Write-Host "`nQuery/Response Balance:" -ForegroundColor Yellow
$totalQueries = ($intervals | Measure-Object -Property QueryCount -Sum).Sum
$totalResponses = ($intervals | Measure-Object -Property ResponseCount -Sum).Sum
$balance = $totalResponses - $totalQueries
Write-Host "  Total Queries: $totalQueries" -ForegroundColor White
Write-Host "  Total Responses: $totalResponses" -ForegroundColor White
Write-Host "  Difference: $balance" -ForegroundColor $(if ([math]::Abs($balance) -gt ($totalQueries * 0.1)) { "Yellow" } else { "Green" })

# WARNING: Response Times missing
Write-Host "`n========================================" -ForegroundColor Red
Write-Host "WARNING: RESPONSE TIMES NOT IN LOG!" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host "The CSV file does not contain 'Total Query Response Time' counter." -ForegroundColor Yellow
Write-Host "This is the most important metric for diagnosing DNS latency issues." -ForegroundColor Yellow
Write-Host "`nTo get response times, run:" -ForegroundColor Cyan
Write-Host "  .\DNS-Performance-Counter-Aktivieren-V2.ps1" -ForegroundColor White
Write-Host "`nThis will recreate the Data Collector Set with Response Time counter." -ForegroundColor Cyan

# Export analysis
$analysisPath = $CsvPath -replace "\.csv$", "_Analysis.csv"
$intervals | Export-Csv -Path $analysisPath -NoTypeInformation -Encoding UTF8
Write-Host "`nDetailed analysis exported to: $analysisPath" -ForegroundColor Green

$intervals
