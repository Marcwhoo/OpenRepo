# DNS Latenz-Ebenen-Analyse
# Testet verschiedene Ebenen der DNS-Aufloesung um zu identifizieren, wo die Latenz entsteht

param(
    [Parameter(Mandatory=$false)]
    [string]$DcName = "<DC-SERVER>",
    [Parameter(Mandatory=$false)]
    [string]$TestDomain = "<DOMAIN-FQDN>",
    [int]$TestCount = 10
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Latenz-Ebenen-Analyse" -ForegroundColor Cyan
Write-Host "Domain: $TestDomain" -ForegroundColor Yellow
Write-Host "DC: $DcName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Test: Resolve-DnsName (kompletter Stack)
Write-Host "1. RESOLVE-DNSNAME (Kompletter DNS-Stack)" -ForegroundColor Cyan
Write-Host "   Inkludiert: PowerShell, DNS-Client-Cache, Zone-Lookups, Netzwerk" -ForegroundColor Gray
$resolveTimes = @()
for ($i = 1; $i -le $TestCount; $i++) {
    $start = Get-Date
    try {
        $result = Resolve-DnsName -Name $TestDomain -Server $DcName -ErrorAction Stop
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        $resolveTimes += $duration
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
if ($resolveTimes.Count -gt 0) {
    $avg = ($resolveTimes | Measure-Object -Average).Average
    $min = ($resolveTimes | Measure-Object -Minimum).Minimum
    $max = ($resolveTimes | Measure-Object -Maximum).Maximum
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" })
}
Write-Host ""

# 2. Test: Resolve-DnsName mit lokalem Server (auf DC selbst)
Write-Host "2. RESOLVE-DNSNAME (Lokal auf DC)" -ForegroundColor Cyan
Write-Host "   Inkludiert: PowerShell, DNS-Client-Cache, Zone-Lookups (lokal), kein Netzwerk" -ForegroundColor Gray
$localTimes = Invoke-Command -ComputerName $DcName -ScriptBlock {
    param($domain, $count)
    $times = @()
    for ($i = 1; $i -le $count; $i++) {
        $start = Get-Date
        try {
            $result = Resolve-DnsName -Name $domain -Server localhost -ErrorAction Stop
            $end = Get-Date
            $duration = ($end - $start).TotalMilliseconds
            $times += $duration
        }
        catch {
            # Ignore errors
        }
    }
    return $times
} -ArgumentList $TestDomain, $TestCount

if ($localTimes.Count -gt 0) {
    $avg = ($localTimes | Measure-Object -Average).Average
    $min = ($localTimes | Measure-Object -Minimum).Minimum
    $max = ($localTimes | Measure-Object -Maximum).Maximum
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" })
}
Write-Host ""

# 3. Test: nslookup (niedrigere Ebene, weniger Overhead)
Write-Host "3. NSLOOKUP (Niedrigere Ebene)" -ForegroundColor Cyan
Write-Host "   Inkludiert: DNS-Client, Netzwerk, weniger PowerShell-Overhead" -ForegroundColor Gray
$nslookupTimes = @()
for ($i = 1; $i -le $TestCount; $i++) {
    $start = Get-Date
    try {
        $result = nslookup $TestDomain $DcName 2>&1 | Out-Null
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        $nslookupTimes += $duration
    }
    catch {
        # Ignore errors
    }
}
if ($nslookupTimes.Count -gt 0) {
    $avg = ($nslookupTimes | Measure-Object -Average).Average
    $min = ($nslookupTimes | Measure-Object -Minimum).Minimum
    $max = ($nslookupTimes | Measure-Object -Maximum).Maximum
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" })
}
Write-Host ""

# 4. Test: DNS-Client-Cache Status
Write-Host "4. DNS-CLIENT-CACHE STATUS" -ForegroundColor Cyan
$cacheInfo = Get-DnsClientCache | Where-Object { $_.Entry -like "*$($TestDomain.Split('.')[0])*" } | Select-Object -First 5
if ($cacheInfo) {
    Write-Host "   Cache-Eintraege gefunden: $($cacheInfo.Count)" -ForegroundColor Yellow
    $cacheInfo | Format-Table Entry, Data, TTL -AutoSize
} else {
    Write-Host "   Keine Cache-Eintraege gefunden" -ForegroundColor Yellow
}
Write-Host ""

# 5. Test: Direkte DNS-Query (mit .NET, minimaler Overhead)
Write-Host "5. DIREKTE DNS-QUERY (.NET)" -ForegroundColor Cyan
Write-Host "   Inkludiert: Nur DNS-Client und Netzwerk, kein PowerShell-Overhead" -ForegroundColor Gray
$dotnetTimes = @()
for ($i = 1; $i -le $TestCount; $i++) {
    $start = Get-Date
    try {
        $result = [System.Net.Dns]::GetHostEntry($TestDomain)
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        $dotnetTimes += $duration
    }
    catch {
        # Ignore errors
    }
}
if ($dotnetTimes.Count -gt 0) {
    $avg = ($dotnetTimes | Measure-Object -Average).Average
    $min = ($dotnetTimes | Measure-Object -Minimum).Minimum
    $max = ($dotnetTimes | Measure-Object -Maximum).Maximum
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" })
}
Write-Host ""

# 6. Test: Mit geleertem Cache
Write-Host "6. RESOLVE-DNSNAME (Nach Cache-Leerung)" -ForegroundColor Cyan
Write-Host "   Cache wird geleert..." -NoNewline
ipconfig /flushdns | Out-Null
Start-Sleep -Seconds 2
Write-Host " OK" -ForegroundColor Green

$flushTimes = @()
for ($i = 1; $i -le $TestCount; $i++) {
    $start = Get-Date
    try {
        $result = Resolve-DnsName -Name $TestDomain -Server $DcName -ErrorAction Stop
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        $flushTimes += $duration
    }
    catch {
        # Ignore errors
    }
}
if ($flushTimes.Count -gt 0) {
    $avg = ($flushTimes | Measure-Object -Average).Average
    $min = ($flushTimes | Measure-Object -Minimum).Minimum
    $max = ($flushTimes | Measure-Object -Maximum).Maximum
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor $(if ($avg -gt 100) { "Red" } elseif ($avg -gt 50) { "Yellow" } else { "Green" })
}
Write-Host ""

# 7. Zusammenfassung und Analyse
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$summary = @()
if ($resolveTimes.Count -gt 0) {
    $summary += [PSCustomObject]@{
        Methode = "Resolve-DnsName (Remote)"
        AvgMs = [math]::Round(($resolveTimes | Measure-Object -Average).Average, 2)
        Ebene = "Kompletter Stack"
    }
}
if ($localTimes.Count -gt 0) {
    $summary += [PSCustomObject]@{
        Methode = "Resolve-DnsName (Lokal auf DC)"
        AvgMs = [math]::Round(($localTimes | Measure-Object -Average).Average, 2)
        Ebene = "Ohne Netzwerk"
    }
}
if ($nslookupTimes.Count -gt 0) {
    $summary += [PSCustomObject]@{
        Methode = "nslookup"
        AvgMs = [math]::Round(($nslookupTimes | Measure-Object -Average).Average, 2)
        Ebene = "Niedrigere Ebene"
    }
}
if ($dotnetTimes.Count -gt 0) {
    $summary += [PSCustomObject]@{
        Methode = ".NET GetHostEntry"
        AvgMs = [math]::Round(($dotnetTimes | Measure-Object -Average).Average, 2)
        Ebene = "Minimaler Overhead"
    }
}
if ($flushTimes.Count -gt 0) {
    $summary += [PSCustomObject]@{
        Methode = "Resolve-DnsName (Cache geleert)"
        AvgMs = [math]::Round(($flushTimes | Measure-Object -Average).Average, 2)
        Ebene = "Ohne Cache"
    }
}

$summary | Format-Table Methode, AvgMs, Ebene -AutoSize

Write-Host ""
Write-Host "ANALYSE:" -ForegroundColor Yellow
if ($resolveTimes.Count -gt 0 -and $localTimes.Count -gt 0) {
    $resolveAvg = ($resolveTimes | Measure-Object -Average).Average
    $localAvg = ($localTimes | Measure-Object -Average).Average
    $diff = $resolveAvg - $localAvg
    
    if ($diff -gt 100) {
        Write-Host "  - Netzwerk-Latenz: ~$([math]::Round($diff, 2))ms" -ForegroundColor Yellow
        Write-Host "  - Lokale Zone-Lookups: ~$([math]::Round($localAvg, 2))ms" -ForegroundColor Yellow
    } else {
        Write-Host "  - Netzwerk-Latenz ist minimal" -ForegroundColor Green
    }
}

if ($resolveTimes.Count -gt 0 -and $dotnetTimes.Count -gt 0) {
    $resolveAvg = ($resolveTimes | Measure-Object -Average).Average
    $dotnetAvg = ($dotnetTimes | Measure-Object -Average).Average
    $diff = $resolveAvg - $dotnetAvg
    
    if ($diff -gt 100) {
        Write-Host "  - PowerShell-Overhead: ~$([math]::Round($diff, 2))ms" -ForegroundColor Yellow
    } else {
        Write-Host "  - PowerShell-Overhead ist minimal" -ForegroundColor Green
    }
}

if ($resolveTimes.Count -gt 0 -and $flushTimes.Count -gt 0) {
    $resolveAvg = ($resolveTimes | Measure-Object -Average).Average
    $flushAvg = ($flushTimes | Measure-Object -Average).Average
    
    if ($flushAvg -gt $resolveAvg) {
        Write-Host "  - Cache hilft: $([math]::Round($resolveAvg, 2))ms vs $([math]::Round($flushAvg, 2))ms" -ForegroundColor Green
    } else {
        Write-Host "  - Cache macht keinen Unterschied" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
