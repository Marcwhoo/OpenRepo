# Detaillierte DNS-Client-Konfiguration-Analyse auf RDS-Hosts

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS-Client-Detail-Analyse auf RDS-Hosts" -ForegroundColor Cyan
Write-Host "NUR LESEN - KEINE AENDERUNGEN!" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

$rdsHosts = @("<INTERNAL-SERVER>-rds01", "<INTERNAL-SERVER>-rds02", "<INTERNAL-SERVER>-rds03", "<INTERNAL-SERVER>-rds04")

function Analyze-DNSClient {
    param([string]$ServerName)
    
    Write-Host "`n=== Analysiere DNS-Client auf $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $data = Invoke-Command -Session $session -ScriptBlock {
            $result = @{}
            
            # 1. DNS-Client-Server-Adressen
            Write-Host "  1. DNS-Client-Server-Adressen..." -NoNewline
            $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $result.DNSServers = $dnsServers | ForEach-Object {
                [PSCustomObject]@{
                    Interface = $_.InterfaceAlias
                    PrimaryDNS = $_.ServerAddresses[0]
                    SecondaryDNS = if ($_.ServerAddresses.Count -gt 1) { $_.ServerAddresses[1] } else { $null }
                    AllDNSServers = $_.ServerAddresses -join ", "
                }
            }
            Write-Host " OK" -ForegroundColor Green
            
            # 2. DNS-Client-Global-Einstellungen
            Write-Host "  2. DNS-Client-Global-Einstellungen..." -NoNewline
            $globalSettings = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue
            $result.GlobalSettings = $globalSettings | Select-Object SuffixSearchList, UseDevolution, DevolutionLevel
            Write-Host " OK" -ForegroundColor Green
            
            # 3. DNS-Client-Cache
            Write-Host "  3. DNS-Client-Cache..." -NoNewline
            $cache = Get-DnsClientCache -ErrorAction SilentlyContinue
            $result.Cache = @{
                Count = $cache.Count
                Entries = $cache | Select-Object -First 20 Entry, RecordName, RecordType, DataLength, TimeToLive
            }
            Write-Host " OK ($($cache.Count) Einträge)" -ForegroundColor Green
            
            # 4. DNS-Client-Service-Status
            Write-Host "  4. DNS-Client-Service..." -NoNewline
            $dnsClientService = Get-Service -Name Dnscache -ErrorAction SilentlyContinue
            $result.DNSClientService = @{
                Status = $dnsClientService.Status
                StartType = $dnsClientService.StartType
            }
            Write-Host " OK" -ForegroundColor Green
            
            # 5. DNS-Client-Registry-Einstellungen
            Write-Host "  5. DNS-Client-Registry-Einstellungen..." -NoNewline
            try {
                $dnsClientParams = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -ErrorAction SilentlyContinue
                $result.RegistrySettings = @{
                    CacheHashTableBucketSize = $dnsClientParams.CacheHashTableBucketSize
                    MaxCacheEntryTtlLimit = $dnsClientParams.MaxCacheEntryTtlLimit
                    MaxNegativeCacheTtl = $dnsClientParams.MaxNegativeCacheTtl
                    NetFailureCacheTime = $dnsClientParams.NetFailureCacheTime
                    NegativeCacheTime = $dnsClientParams.NegativeCacheTime
                    NegativeSOACacheTime = $dnsClientParams.NegativeSOACacheTime
                }
                Write-Host " OK" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $result.RegistrySettings = @{ Error = $_.Exception.Message }
            }
            
            # 6. DNS-Client-Performance-Test
            Write-Host "  6. DNS-Client-Performance-Test..." -NoNewline
            $testTimes = @()
            for ($i = 1; $i -le 20; $i++) {
                $start = Get-Date
                try {
                    $null = Resolve-DnsName -Name "<DC-SERVER>.<DOMAIN-FQDN>" -Type A -ErrorAction Stop
                    $end = Get-Date
                    $testTimes += ($end - $start).TotalMilliseconds
                }
                catch { }
            }
            
            if ($testTimes.Count -gt 0) {
                $result.PerformanceTest = @{
                    AverageMS = [math]::Round(($testTimes | Measure-Object -Average).Average, 2)
                    MinMS = [math]::Round(($testTimes | Measure-Object -Minimum).Minimum, 2)
                    MaxMS = [math]::Round(($testTimes | Measure-Object -Maximum).Maximum, 2)
                    MedianMS = [math]::Round(($testTimes | Sort-Object)[[math]::Floor($testTimes.Count / 2)], 2)
                }
            }
            Write-Host " OK" -ForegroundColor Green
            
            return $result
        }
        
        Remove-PSSession $session
        return $data
    }
    catch {
        Write-Warning "Fehler bei $ServerName : $($_.Exception.Message)"
        return $null
    }
}

# Analysiere alle RDS-Hosts
$allResults = @{}

foreach ($rdsHost in $rdsHosts) {
    $allResults[$rdsHost] = Analyze-DNSClient -ServerName $rdsHost
}

# Vergleich
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VERGLEICH" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# DNS-Server-Reihenfolge
Write-Host "`nDNS-Server-Reihenfolge:" -ForegroundColor Yellow
foreach ($rdsHost in $rdsHosts) {
    if ($allResults[$rdsHost] -and $allResults[$rdsHost].DNSServers) {
        $primary = $allResults[$rdsHost].DNSServers[0].PrimaryDNS
        Write-Host "  $rdsHost : Primär=$primary" -ForegroundColor $(if ($primary -eq "<IP-ADDRESS>") { "Yellow" } else { "Green" })
    }
}

# DNS-Client-Cache
Write-Host "`nDNS-Client-Cache:" -ForegroundColor Yellow
foreach ($rdsHost in $rdsHosts) {
    if ($allResults[$rdsHost] -and $allResults[$rdsHost].Cache) {
        Write-Host "  $rdsHost : $($allResults[$rdsHost].Cache.Count) Einträge" -ForegroundColor Green
    }
}

# Performance-Test
Write-Host "`nDNS-Client-Performance-Test:" -ForegroundColor Yellow
foreach ($rdsHost in $rdsHosts) {
    if ($allResults[$rdsHost] -and $allResults[$rdsHost].PerformanceTest) {
        $perf = $allResults[$rdsHost].PerformanceTest
        Write-Host "  $rdsHost : $($perf.AverageMS) ms (Min: $($perf.MinMS), Max: $($perf.MaxMS))" -ForegroundColor $(if ($perf.AverageMS -gt 50) { "Red" } else { "Green" })
    }
}

# Registry-Einstellungen vergleichen
Write-Host "`nDNS-Client-Registry-Einstellungen:" -ForegroundColor Yellow
$firstHost = $rdsHosts[0]
if ($allResults[$firstHost] -and $allResults[$firstHost].RegistrySettings) {
    $firstSettings = $allResults[$firstHost].RegistrySettings
    Write-Host "  $firstHost (Referenz):" -ForegroundColor Cyan
    foreach ($key in $firstSettings.Keys) {
        if ($key -ne "Error") {
            Write-Host "    $key = $($firstSettings[$key])" -ForegroundColor White
        }
    }
    
    $differences = @()
    foreach ($rdsHost in $rdsHosts[1..($rdsHosts.Count-1)]) {
        if ($allResults[$rdsHost] -and $allResults[$rdsHost].RegistrySettings) {
            $settings = $allResults[$rdsHost].RegistrySettings
            foreach ($key in $firstSettings.Keys) {
                if ($key -ne "Error" -and $firstSettings[$key] -ne $settings[$key]) {
                    $differences += "$rdsHost : $key unterschiedlich ($($firstSettings[$key]) vs. $($settings[$key]))"
                }
            }
        }
    }
    
    if ($differences.Count -gt 0) {
        Write-Host "  WARNUNG: Unterschiede gefunden:" -ForegroundColor Red
        $differences | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    }
    else {
        Write-Host "  Alle Hosts haben identische Registry-Einstellungen" -ForegroundColor Green
    }
}

# Speichere Ergebnisse
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    RDSHosts = $allResults
}

$jsonPath = ".\DNS-Client-Detail-Analyse-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Ergebnisse gespeichert ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

$results
