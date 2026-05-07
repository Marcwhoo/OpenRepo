# DNS SOA Record Configuration Analysis
# Checks SOA record configuration for zones

param(
    [string]$DcName = "<DC-SERVER>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS SOA Record Configuration Analysis" -ForegroundColor Cyan
Write-Host "DC: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. SOA Record for <DOMAIN-FQDN>
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. SOA RECORD: <DOMAIN-FQDN>" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $soaRecord = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        if ($zone) {
            $soa = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -RRType SOA -ErrorAction SilentlyContinue
            if ($soa) {
                return @{
                    ZoneName = $zone.ZoneName
                    ZoneType = $zone.ZoneType
                    PrimaryServer = $soa.RecordData.PrimaryServer
                    ResponsiblePerson = $soa.RecordData.ResponsiblePerson
                    SerialNumber = $soa.RecordData.SerialNumber
                    RefreshInterval = $soa.RecordData.RefreshInterval
                    RetryInterval = $soa.RecordData.RetryInterval
                    ExpireLimit = $soa.RecordData.ExpireLimit
                    MinimumTimeToLive = $soa.RecordData.MinimumTimeToLive
                    TimeToLive = $soa.TimeToLive
                }
            }
        }
        return $null
    }
    
    if ($soaRecord) {
        Write-Host "Zone Name: $($soaRecord.ZoneName)" -ForegroundColor White
        Write-Host "Zone Type: $($soaRecord.ZoneType)" -ForegroundColor White
        Write-Host "Primary Server: $($soaRecord.PrimaryServer)" -ForegroundColor White
        Write-Host "Responsible Person: $($soaRecord.ResponsiblePerson)" -ForegroundColor White
        Write-Host "Serial Number: $($soaRecord.SerialNumber)" -ForegroundColor White
        Write-Host ""
        Write-Host "SOA Timing Parameters:" -ForegroundColor Yellow
        $refreshHours = [math]::Round($soaRecord.RefreshInterval.TotalHours, 2)
        $retryHours = [math]::Round($soaRecord.RetryInterval.TotalHours, 2)
        $expireDays = [math]::Round($soaRecord.ExpireLimit.TotalDays, 2)
        $minTtlMinutes = [math]::Round($soaRecord.MinimumTimeToLive.TotalMinutes, 2)
        $ttlMinutes = [math]::Round($soaRecord.TimeToLive.TotalMinutes, 2)
        
        Write-Host "  Refresh Interval: $($soaRecord.RefreshInterval) ($refreshHours hours)" -ForegroundColor White
        Write-Host "  Retry Interval: $($soaRecord.RetryInterval) ($retryHours hours)" -ForegroundColor White
        Write-Host "  Expire Limit: $($soaRecord.ExpireLimit) ($expireDays days)" -ForegroundColor White
        Write-Host "  Minimum TTL: $($soaRecord.MinimumTimeToLive) ($minTtlMinutes minutes)" -ForegroundColor White
        Write-Host "  Record TTL: $($soaRecord.TimeToLive) ($ttlMinutes minutes)" -ForegroundColor White
        
        if ($soaRecord.RefreshInterval -gt 86400) {
            Write-Host "  WARNING: Refresh Interval is very high (>24h) - may cause slow zone transfers" -ForegroundColor Yellow
        }
        if ($soaRecord.MinimumTimeToLive -gt 3600) {
            Write-Host "  WARNING: Minimum TTL is very high (>1h) - may cause slow cache updates" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not retrieve SOA record" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 2. SOA Record for Reverse Zone
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. SOA RECORD: <REVERSE-ZONE>" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $reverseSoa = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<REVERSE-ZONE>" -ErrorAction SilentlyContinue
        if ($zone) {
            $soa = Get-DnsServerResourceRecord -ZoneName "<REVERSE-ZONE>" -RRType SOA -ErrorAction SilentlyContinue
            if ($soa) {
                return @{
                    ZoneName = $zone.ZoneName
                    ZoneType = $zone.ZoneType
                    PrimaryServer = $soa.RecordData.PrimaryServer
                    ResponsiblePerson = $soa.RecordData.ResponsiblePerson
                    SerialNumber = $soa.RecordData.SerialNumber
                    RefreshInterval = $soa.RecordData.RefreshInterval
                    RetryInterval = $soa.RecordData.RetryInterval
                    ExpireLimit = $soa.RecordData.ExpireLimit
                    MinimumTimeToLive = $soa.RecordData.MinimumTimeToLive
                    TimeToLive = $soa.TimeToLive
                }
            }
        }
        return $null
    }
    
    if ($reverseSoa) {
        Write-Host "Zone Name: $($reverseSoa.ZoneName)" -ForegroundColor White
        Write-Host "Zone Type: $($reverseSoa.ZoneType)" -ForegroundColor White
        Write-Host "Primary Server: $($reverseSoa.PrimaryServer)" -ForegroundColor White
        Write-Host "Responsible Person: $($reverseSoa.ResponsiblePerson)" -ForegroundColor White
        Write-Host "Serial Number: $($reverseSoa.SerialNumber)" -ForegroundColor White
        Write-Host ""
        Write-Host "SOA Timing Parameters:" -ForegroundColor Yellow
        $refreshHours = [math]::Round($reverseSoa.RefreshInterval.TotalHours, 2)
        $retryHours = [math]::Round($reverseSoa.RetryInterval.TotalHours, 2)
        $expireDays = [math]::Round($reverseSoa.ExpireLimit.TotalDays, 2)
        $minTtlMinutes = [math]::Round($reverseSoa.MinimumTimeToLive.TotalMinutes, 2)
        $ttlMinutes = [math]::Round($reverseSoa.TimeToLive.TotalMinutes, 2)
        
        Write-Host "  Refresh Interval: $($reverseSoa.RefreshInterval) ($refreshHours hours)" -ForegroundColor White
        Write-Host "  Retry Interval: $($reverseSoa.RetryInterval) ($retryHours hours)" -ForegroundColor White
        Write-Host "  Expire Limit: $($reverseSoa.ExpireLimit) ($expireDays days)" -ForegroundColor White
        Write-Host "  Minimum TTL: $($reverseSoa.MinimumTimeToLive) ($minTtlMinutes minutes)" -ForegroundColor White
        Write-Host "  Record TTL: $($reverseSoa.TimeToLive) ($ttlMinutes minutes)" -ForegroundColor White
    } else {
        Write-Host "Could not retrieve SOA record" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Compare SOA Records
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. SOA RECORD COMPARISON" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($soaRecord -and $reverseSoa) {
    Write-Host "Comparing SOA records..." -ForegroundColor Yellow
    Write-Host ""
    
    if ($soaRecord.RefreshInterval -ne $reverseSoa.RefreshInterval) {
        Write-Host "WARNING: Refresh Interval differs between zones" -ForegroundColor Yellow
    }
    if ($soaRecord.MinimumTimeToLive -ne $reverseSoa.MinimumTimeToLive) {
        Write-Host "WARNING: Minimum TTL differs between zones" -ForegroundColor Yellow
    }
    if ($soaRecord.PrimaryServer -ne $reverseSoa.PrimaryServer) {
        Write-Host "INFO: Primary Server differs between zones" -ForegroundColor White
    }
}

# 4. Test SOA Query Performance
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. SOA QUERY PERFORMANCE TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Testing SOA query performance..." -ForegroundColor Yellow
$testDomains = @("<DOMAIN-FQDN>", "<REVERSE-ZONE>")

foreach ($domain in $testDomains) {
    Write-Host ""
    Write-Host "Domain: $domain" -ForegroundColor Yellow
    $times = @()
    for ($i = 1; $i -le 10; $i++) {
        $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($d)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $soa = Resolve-DnsName -Name $d -Type SOA -ErrorAction SilentlyContinue
            } catch {}
            $sw.Stop()
            return $sw.ElapsedMilliseconds
        } -ArgumentList $domain
        $times += $result
    }
    $avg = ($times | Measure-Object -Average).Average
    $max = ($times | Measure-Object -Maximum).Maximum
    $min = ($times | Measure-Object -Minimum).Minimum
    
    Write-Host "  Avg: $([math]::Round($avg, 2))ms" -ForegroundColor $(if ($avg -gt 50) { "Red" } elseif ($avg -gt 10) { "Yellow" } else { "White" })
    Write-Host "  Min: $([math]::Round($min, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($max -gt 100) { "Red" } else { "White" })
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
