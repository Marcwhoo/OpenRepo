# DNS Service Memory and Performance Analysis
# Checks DNS service memory usage over time and after restart

param(
    [string]$DcName = "<DC-SERVER>",
    [int]$TestDurationMinutes = 5,
    [int]$SampleIntervalSeconds = 30
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Service Memory Analysis" -ForegroundColor Cyan
Write-Host "DC: $DcName" -ForegroundColor Yellow
Write-Host "Duration: $TestDurationMinutes minutes" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$samples = New-Object System.Collections.ArrayList
$testDomain = "<DOMAIN-FQDN>"
$totalSamples = ($TestDurationMinutes * 60) / $SampleIntervalSeconds

Write-Host "Collecting $totalSamples samples over $TestDurationMinutes minutes..." -ForegroundColor Yellow
Write-Host "Sample interval: $SampleIntervalSeconds seconds" -ForegroundColor Yellow
Write-Host ""

for ($i = 1; $i -le $totalSamples; $i++) {
    $sample = Invoke-Command -ComputerName $DcName -ScriptBlock {
        param($domain)
        
        $dnsService = Get-Service -Name DNS
        $dnsProcess = Get-Process -Name dns -ErrorAction SilentlyContinue
        
        $memoryMB = 0
        $threads = 0
        $handles = 0
        if ($dnsProcess) {
            $memoryMB = [math]::Round($dnsProcess.WorkingSet64 / 1MB, 2)
            $threads = $dnsProcess.Threads.Count
            $handles = $dnsProcess.HandleCount
        }
        
        $dnsTimes = @()
        for ($j = 1; $j -le 3; $j++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Resolve-DnsName -Name $domain -ErrorAction SilentlyContinue | Out-Null
            } catch {}
            $sw.Stop()
            $dnsTimes += $sw.ElapsedMilliseconds
        }
        $avgDnsTime = ($dnsTimes | Measure-Object -Average).Average
        
        return [PSCustomObject]@{
            Timestamp = Get-Date
            MemoryMB = $memoryMB
            Threads = $threads
            Handles = $handles
            AvgDnsTimeMs = [math]::Round($avgDnsTime, 2)
        }
    } -ArgumentList $testDomain
    
    [void]$samples.Add($sample)
    
    Write-Host "[$i/$totalSamples] Memory: $($sample.MemoryMB)MB | Threads: $($sample.Threads) | DNS: $($sample.AvgDnsTimeMs)ms" -ForegroundColor White
    
    if ($i -lt $totalSamples) {
        Start-Sleep -Seconds $SampleIntervalSeconds
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ANALYSIS RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$memoryValues = $samples | ForEach-Object { $_.MemoryMB }
$dnsTimeValues = $samples | ForEach-Object { $_.AvgDnsTimeMs }

$memoryStart = $memoryValues[0]
$memoryEnd = $memoryValues[-1]
$memoryMin = ($memoryValues | Measure-Object -Minimum).Minimum
$memoryMax = ($memoryValues | Measure-Object -Maximum).Maximum
$memoryAvg = ($memoryValues | Measure-Object -Average).Average

$dnsTimeStart = $dnsTimeValues[0]
$dnsTimeEnd = $dnsTimeValues[-1]
$dnsTimeMin = ($dnsTimeValues | Measure-Object -Minimum).Minimum
$dnsTimeMax = ($dnsTimeValues | Measure-Object -Maximum).Maximum
$dnsTimeAvg = ($dnsTimeValues | Measure-Object -Average).Average

Write-Host ""
Write-Host "Memory Usage:" -ForegroundColor Yellow
Write-Host "  Start: $memoryStart MB" -ForegroundColor White
Write-Host "  End: $memoryEnd MB" -ForegroundColor White
Write-Host "  Min: $memoryMin MB" -ForegroundColor White
Write-Host "  Max: $memoryMax MB" -ForegroundColor White
Write-Host "  Average: $([math]::Round($memoryAvg, 2)) MB" -ForegroundColor White

$memoryChange = $memoryEnd - $memoryStart
if ($memoryChange -gt 5) {
    Write-Host "  WARNING: Memory increased by $([math]::Round($memoryChange, 2)) MB - possible memory leak!" -ForegroundColor Red
} elseif ($memoryChange -lt -5) {
    Write-Host "  Memory decreased by $([math]::Round([Math]::Abs($memoryChange), 2)) MB" -ForegroundColor Green
} else {
    Write-Host "  Memory stable (change: $([math]::Round($memoryChange, 2)) MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "DNS Resolution Time:" -ForegroundColor Yellow
Write-Host "  Start: $dnsTimeStart ms" -ForegroundColor White
Write-Host "  End: $dnsTimeEnd ms" -ForegroundColor White
Write-Host "  Min: $dnsTimeMin ms" -ForegroundColor White
Write-Host "  Max: $dnsTimeMax ms" -ForegroundColor White
Write-Host "  Average: $([math]::Round($dnsTimeAvg, 2)) ms" -ForegroundColor White

$dnsTimeChange = $dnsTimeEnd - $dnsTimeStart
if ($dnsTimeChange -gt 50) {
    Write-Host "  WARNING: DNS resolution slowed down by $([math]::Round($dnsTimeChange, 2)) ms!" -ForegroundColor Red
} elseif ($dnsTimeChange -lt -50) {
    Write-Host "  DNS resolution improved by $([math]::Round([Math]::Abs($dnsTimeChange), 2)) ms" -ForegroundColor Green
} else {
    Write-Host "  DNS resolution stable (change: $([math]::Round($dnsTimeChange, 2)) ms)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Correlation Analysis:" -ForegroundColor Yellow
if ($memoryChange -gt 5 -and $dnsTimeChange -gt 50) {
    Write-Host "  STRONG CORRELATION: Memory increase correlates with DNS slowdown!" -ForegroundColor Red
    Write-Host "  Recommendation: Schedule regular DNS service restarts or investigate memory leak" -ForegroundColor Yellow
} elseif ($memoryChange -gt 5) {
    Write-Host "  Memory increased but DNS performance stable" -ForegroundColor Yellow
} elseif ($dnsTimeChange -gt 50) {
    Write-Host "  DNS slowed down but memory stable - investigate other causes" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
