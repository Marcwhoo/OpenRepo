# DNS Wireshark Analysis - <DOMAIN-FQDN> Focus
# Analyzes CSV from Slim script or extracts directly

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
Write-Host "DNS Wireshark Analysis - <DOMAIN-FQDN>" -ForegroundColor Cyan
Write-Host "File: $PcapngFile" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# First try to use Slim script to get matched queries
Write-Host "Running Slim analysis to get matched queries..." -ForegroundColor Yellow
$slimScript = Join-Path $PSScriptRoot "DNS-Wireshark-Analyse-Slim.ps1"
if (Test-Path $slimScript) {
    $slimOutput = & $slimScript -PcapngFile $PcapngFile -SlowThresholdMs 0 2>&1
    Write-Host "Slim analysis completed" -ForegroundColor Green
}

# Extract DNS requests directly (no matching needed for domain analysis)
Write-Host "Extracting DNS requests..." -NoNewline
$fields = @(
    "frame.time_relative",
    "ip.src",
    "ip.dst",
    "dns.qry.name",
    "dns.qry.type"
)

$tsharkArgs = @("-r", $PcapngFile, "-Y", "dns.flags.response == 0", "-T", "fields")
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

# Parse requests
Write-Host "Parsing requests..." -NoNewline
$requests = [System.Collections.Generic.List[object]]::new()
foreach ($line in $rawData) {
    if ($line -match '^\t') { continue }
    $fields = $line -split '\t'
    if ($fields.Count -ge 5) {
        try {
            $request = [PSCustomObject]@{
                TimeRelative = if ($fields[0]) { [double]$fields[0] } else { 0 }
                SourceIp = if ($fields[1]) { $fields[1] } else { "" }
                DestIp = if ($fields[2]) { $fields[2] } else { "" }
                QueryName = if ($fields[3]) { $fields[3] } else { "" }
                QueryType = if ($fields[4]) { $fields[4] } else { "" }
                IsInternal = ($fields[2] -eq "<IP-ADDRESS>" -or $fields[2] -eq "<IP-ADDRESS>")
            }
            [void]$requests.Add($request)
        }
        catch { }
    }
}
Write-Host " OK ($($requests.Count) requests)" -ForegroundColor Green
Write-Host ""

# Analyze <DOMAIN-FQDN> queries
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "<DOMAIN-FQDN> QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$domainQueries = $requests | Where-Object { 
    $_.QueryName -match "<DOMAIN-FQDN>" -or 
    $_.QueryName -match "<DOMAIN-FQDN>" -or
    $_.QueryName -match "\.<DOMAIN-FQDN>" -or
    $_.QueryName -match "\.<DOMAIN-FQDN>"
}

if ($domainQueries.Count -eq 0) {
    Write-Host "No <DOMAIN-FQDN> queries found in trace!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Top 30 domains queried:" -ForegroundColor Yellow
    $topDomains = $requests | Group-Object QueryName | Sort-Object Count -Descending | Select-Object -First 30
    $topDomains | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Searching for any '<domain>' in query names..." -ForegroundColor Yellow
    $domainAny = $requests | Where-Object { $_.QueryName -match "<DOMAIN-NETBIOS>" -or $_.QueryName -match "<DOMAIN-NETBIOS>" }
    Write-Host "Found $($domainAny.Count) queries containing '<domain>'" -ForegroundColor White
    if ($domainAny.Count -gt 0) {
        $domainAny | Group-Object QueryName | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Count) queries" -ForegroundColor White
        }
    }
}
else {
    Write-Host "Total <DOMAIN-FQDN> queries: $($domainQueries.Count)" -ForegroundColor White
    
    $internalDomain = $domainQueries | Where-Object { $_.IsInternal }
    $externalDomain = $domainQueries | Where-Object { -not $_.IsInternal }
    
    Write-Host "  Internal (to <IP-ADDRESS>/12): $($internalDomain.Count)" -ForegroundColor White
    Write-Host "  External (to other DNS): $($externalDomain.Count)" -ForegroundColor White
    
    Write-Host ""
    Write-Host "<DOMAIN-FQDN> queries by type:" -ForegroundColor Yellow
    $byType = $domainQueries | Group-Object QueryType | Sort-Object Count -Descending
    $byType | ForEach-Object {
        Write-Host "  Type $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Top 20 <DOMAIN-FQDN> query names:" -ForegroundColor Yellow
    $byName = $domainQueries | Group-Object QueryName | Sort-Object Count -Descending | Select-Object -First 20
    $byName | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Top sources querying <DOMAIN-FQDN>:" -ForegroundColor Yellow
    $bySource = $domainQueries | Group-Object SourceIp | Sort-Object Count -Descending | Select-Object -First 10
    $bySource | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) queries" -ForegroundColor White
    }
}

# Internal vs External analysis
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INTERNAL vs EXTERNAL QUERIES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$internalQueries = $requests | Where-Object { $_.IsInternal }
$externalQueries = $requests | Where-Object { -not $_.IsInternal }

Write-Host "Internal Queries (to <IP-ADDRESS>/12):" -ForegroundColor Yellow
Write-Host "  Count: $($internalQueries.Count)" -ForegroundColor White
Write-Host "  Percentage: $([math]::Round(($internalQueries.Count / $requests.Count) * 100, 1))%" -ForegroundColor White

Write-Host ""
Write-Host "External Queries (to other DNS servers):" -ForegroundColor Yellow
Write-Host "  Count: $($externalQueries.Count)" -ForegroundColor White
Write-Host "  Percentage: $([math]::Round(($externalQueries.Count / $requests.Count) * 100, 1))%" -ForegroundColor White

# Top domains
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP 30 DOMAINS BY QUERY COUNT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$domainStats = $requests | Group-Object QueryName | ForEach-Object {
    $queries = $_.Group
    $internal = ($queries | Where-Object { $_.IsInternal }).Count
    
    [PSCustomObject]@{
        Domain = $_.Name
        QueryCount = $queries.Count
        InternalQueries = $internal
        ExternalQueries = $queries.Count - $internal
    }
} | Sort-Object QueryCount -Descending | Select-Object -First 30

$domainStats | Format-Table Domain, QueryCount, InternalQueries, ExternalQueries -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "ERKLAERUNG:" -ForegroundColor Yellow
Write-Host "Die DNS-Cache-Analyse zeigt 900-1000ms, weil sie Resolve-DnsName verwendet," -ForegroundColor White
Write-Host "was den kompletten DNS-Stack durchlaeuft (inkl. Cache-Checks, Zone-Lookups, etc.)." -ForegroundColor White
Write-Host ""
Write-Host "Die Wireshark-Analyse zeigt 3.46ms avg, weil sie nur die tatsaechlichen" -ForegroundColor White
Write-Host "DNS-Pakete im Netzwerk misst (Request -> Response)." -ForegroundColor White
Write-Host ""
Write-Host "Wenn keine <DOMAIN-FQDN> Queries im Trace sind, bedeutet das:" -ForegroundColor White
Write-Host "- Die Queries werden gecacht (Client-Cache)" -ForegroundColor White
Write-Host "- Oder die Queries gehen an einen anderen DNS-Server" -ForegroundColor White
Write-Host "- Oder es wurden keine <DOMAIN-FQDN> Queries waehrend des Traces gemacht" -ForegroundColor White
