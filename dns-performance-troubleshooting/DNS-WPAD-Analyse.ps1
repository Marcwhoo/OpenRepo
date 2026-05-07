# DNS WPAD Record Analysis
# Analyzes wpad.<DOMAIN-FQDN> DNS configuration and performance

param(
    [string]$DcName = "<DC-SERVER>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS WPAD Record Analysis" -ForegroundColor Cyan
Write-Host "DC: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check WPAD Record
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. WPAD RECORD CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $wpadRecord = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $records = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -Name "wpad" -ErrorAction SilentlyContinue
        if ($records) {
            return $records | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.HostName
                    RecordType = $_.RecordType
                    RecordData = $_.RecordData
                    TimeToLive = $_.TimeToLive
                    Timestamp = $_.Timestamp
                }
            }
        }
        return $null
    }
    
    if ($wpadRecord) {
        Write-Host "Found $($wpadRecord.Count) WPAD record(s):" -ForegroundColor Green
        foreach ($record in $wpadRecord) {
            Write-Host ""
            Write-Host "  Name: $($record.Name)" -ForegroundColor White
            Write-Host "  Type: $($record.RecordType)" -ForegroundColor White
            Write-Host "  TTL: $($record.TimeToLive) seconds ($([math]::Round($record.TimeToLive / 60, 2)) minutes)" -ForegroundColor White
            Write-Host "  Data: $($record.RecordData)" -ForegroundColor White
            if ($record.Timestamp) {
                Write-Host "  Timestamp: $($record.Timestamp)" -ForegroundColor White
            }
        }
    } else {
        Write-Host "No WPAD record found in zone <DOMAIN-FQDN>" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 2. Test WPAD Resolution Performance
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. WPAD RESOLUTION PERFORMANCE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Testing wpad.<DOMAIN-FQDN> resolution..." -ForegroundColor Yellow
$times = @()
for ($i = 1; $i -le 20; $i++) {
    $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $result = Resolve-DnsName -Name "wpad.<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        } catch {}
        $sw.Stop()
        return $sw.ElapsedMilliseconds
    }
    $times += $result
    if ($i % 5 -eq 0) {
        Write-Host "  Test $i/20..." -ForegroundColor Yellow
    }
}

$avg = ($times | Measure-Object -Average).Average
$max = ($times | Measure-Object -Maximum).Maximum
$min = ($times | Measure-Object -Minimum).Minimum
$slow = ($times | Where-Object { $_ -gt 100 }).Count

Write-Host ""
Write-Host "Results:" -ForegroundColor Yellow
Write-Host "  Average: $([math]::Round($avg, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "White" })
Write-Host "  Min: $([math]::Round($min, 2))ms" -ForegroundColor White
Write-Host "  Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($max -gt 100) { "Red" } else { "White" })
Write-Host "  Slow Queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Red" } else { "Green" })

# 3. Check WPAD in Wireshark Data
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. WPAD QUERIES IN WIRESHARK DATA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$csvFile = "DNS-Trace\DNS-Trace-2026-01-23_09-55-32-Analysis.csv"
if (Test-Path $csvFile) {
    Write-Host "Analyzing WPAD queries from Wireshark data..." -ForegroundColor Yellow
    $queries = Import-Csv $csvFile
    $queries = $queries | ForEach-Object {
        $rt = $_.ResponseTimeMs -replace ',', '.'
        $_.ResponseTimeMs = [double]$rt
        $_
    }
    
    $wpadQueries = $queries | Where-Object { $_.QueryName -like "*wpad*" }
    
    if ($wpadQueries.Count -gt 0) {
        Write-Host "Found $($wpadQueries.Count) WPAD queries:" -ForegroundColor Green
        $avg = ($wpadQueries | Measure-Object -Property ResponseTimeMs -Average).Average
        $max = ($wpadQueries | Measure-Object -Property ResponseTimeMs -Maximum).Maximum
        $min = ($wpadQueries | Measure-Object -Property ResponseTimeMs -Minimum).Minimum
        $slow = ($wpadQueries | Where-Object { $_.ResponseTimeMs -gt 100 }).Count
        
        Write-Host "  Average: $([math]::Round($avg, 2))ms" -ForegroundColor White
        Write-Host "  Min: $([math]::Round($min, 2))ms" -ForegroundColor White
        Write-Host "  Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($max -gt 100) { "Red" } else { "White" })
        Write-Host "  Slow Queries (>100ms): $slow" -ForegroundColor $(if ($slow -gt 0) { "Red" } else { "Green" })
        
        Write-Host ""
        Write-Host "Top 10 slowest WPAD queries:" -ForegroundColor Yellow
        $wpadQueries | Sort-Object ResponseTimeMs -Descending | Select-Object -First 10 | Format-Table ResponseTimeMs, QueryName, SourceIp, DnsServer -AutoSize
    } else {
        Write-Host "No WPAD queries found in Wireshark data" -ForegroundColor Yellow
    }
} else {
    Write-Host "Wireshark CSV file not found: $csvFile" -ForegroundColor Yellow
}

# 4. Check WPAD Record Count
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. WPAD RECORD COUNT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $wpadCount = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $records = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -Name "wpad" -ErrorAction SilentlyContinue
        return $records.Count
    }
    
    Write-Host "WPAD records in zone: $wpadCount" -ForegroundColor White
    if ($wpadCount -gt 1) {
        Write-Host "WARNING: Multiple WPAD records found - may cause resolution issues" -ForegroundColor Yellow
    } elseif ($wpadCount -eq 0) {
        Write-Host "WARNING: No WPAD record found - clients may timeout waiting for WPAD" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
