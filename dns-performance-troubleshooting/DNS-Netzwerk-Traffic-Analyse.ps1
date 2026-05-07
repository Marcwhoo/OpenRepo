# DNS-Netzwerk-Traffic-Analyse (ohne Wireshark)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS-Netzwerk-Traffic-Analyse" -ForegroundColor Cyan
Write-Host "NUR LESEN - KEINE AENDERUNGEN!" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nHINWEIS: Wireshark-Trace kann nicht automatisch durchgeführt werden." -ForegroundColor Yellow
Write-Host "Diese Analyse verwendet PowerShell-Netzwerk-Statistiken und Performance-Counter." -ForegroundColor Yellow

function Analyze-NetworkTraffic {
    param([string]$ServerName)
    
    Write-Host "`n=== Analysiere Netzwerk-Traffic auf $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $data = Invoke-Command -Session $session -ScriptBlock {
            $result = @{}
            
            # 1. Netzwerk-Adapter-Statistiken (vor Test)
            Write-Host "  1. Netzwerk-Adapter-Statistiken (vor Test)..." -NoNewline
            $adapterStatsBefore = Get-NetAdapterStatistics | Where-Object { $_.LinkSpeed -gt 0 }
            $result.AdapterStatsBefore = $adapterStatsBefore | Select-Object Name, ReceivedBytes, SentBytes, ReceivedPackets, SentPackets
            Write-Host " OK" -ForegroundColor Green
            
            # 2. DNS-Abfragen durchführen und Traffic messen
            Write-Host "  2. Führe DNS-Abfragen durch..." -NoNewline
            $dnsQueries = 0
            $dnsErrors = 0
            $queryTimes = @()
            
            for ($i = 1; $i -le 50; $i++) {
                $start = Get-Date
                try {
                    $null = Resolve-DnsName -Name "<DC-SERVER>.<DOMAIN-FQDN>" -Type A -ErrorAction Stop
                    $end = Get-Date
                    $queryTimes += ($end - $start).TotalMilliseconds
                    $dnsQueries++
                }
                catch {
                    $dnsErrors++
                }
            }
            
            $result.DNSTest = @{
                Queries = $dnsQueries
                Errors = $dnsErrors
                AverageMS = if ($queryTimes.Count -gt 0) { [math]::Round(($queryTimes | Measure-Object -Average).Average, 2) } else { 0 }
                MinMS = if ($queryTimes.Count -gt 0) { [math]::Round(($queryTimes | Measure-Object -Minimum).Minimum, 2) } else { 0 }
                MaxMS = if ($queryTimes.Count -gt 0) { [math]::Round(($queryTimes | Measure-Object -Maximum).Maximum, 2) } else { 0 }
            }
            Write-Host " OK ($dnsQueries Abfragen, $dnsErrors Fehler)" -ForegroundColor Green
            
            # 3. Netzwerk-Adapter-Statistiken (nach Test)
            Write-Host "  3. Netzwerk-Adapter-Statistiken (nach Test)..." -NoNewline
            Start-Sleep -Seconds 2
            $adapterStatsAfter = Get-NetAdapterStatistics | Where-Object { $_.LinkSpeed -gt 0 }
            $result.AdapterStatsAfter = $adapterStatsAfter | Select-Object Name, ReceivedBytes, SentBytes, ReceivedPackets, SentPackets
            
            # Berechne Differenz
            $result.TrafficDiff = @()
            foreach ($adapterBefore in $adapterStatsBefore) {
                $adapterAfter = $adapterStatsAfter | Where-Object { $_.Name -eq $adapterBefore.Name }
                if ($adapterAfter) {
                    $result.TrafficDiff += [PSCustomObject]@{
                        Name = $adapterBefore.Name
                        ReceivedBytes = $adapterAfter.ReceivedBytes - $adapterBefore.ReceivedBytes
                        SentBytes = $adapterAfter.SentBytes - $adapterBefore.SentBytes
                        ReceivedPackets = $adapterAfter.ReceivedPackets - $adapterBefore.ReceivedPackets
                        SentPackets = $adapterAfter.SentPackets - $adapterBefore.SentPackets
                    }
                }
            }
            Write-Host " OK" -ForegroundColor Green
            
            # 4. TCP-Verbindungen zu DNS-Port 53
            Write-Host "  4. TCP-Verbindungen zu Port 53..." -NoNewline
            try {
                $tcpConnections = Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue
                $result.TCPConnections53 = @{
                    Count = $tcpConnections.Count
                    Connections = $tcpConnections | Select-Object LocalAddress, RemoteAddress, State, OwningProcess
                }
                Write-Host " OK ($($tcpConnections.Count) Verbindungen)" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $result.TCPConnections53 = @{ Error = $_.Exception.Message }
            }
            
            # 5. UDP-Verbindungen zu DNS-Port 53
            Write-Host "  5. UDP-Verbindungen zu Port 53..." -NoNewline
            try {
                $udpConnections = Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue
                $result.UDPConnections53 = @{
                    Count = $udpConnections.Count
                    Connections = $udpConnections | Select-Object LocalAddress, OwningProcess
                }
                Write-Host " OK ($($udpConnections.Count) Verbindungen)" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $result.UDPConnections53 = @{ Error = $_.Exception.Message }
            }
            
            # 6. DNS-Client-Cache-Statistiken
            Write-Host "  6. DNS-Client-Cache-Statistiken..." -NoNewline
            try {
                $cache = Get-DnsClientCache -ErrorAction SilentlyContinue
                $result.CacheStats = @{
                    Count = $cache.Count
                    ByType = $cache | Group-Object RecordType | ForEach-Object {
                        [PSCustomObject]@{
                            Type = $_.Name
                            Count = $_.Count
                        }
                    }
                }
                Write-Host " OK ($($cache.Count) Einträge)" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $result.CacheStats = @{ Error = $_.Exception.Message }
            }
            
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

# Analysiere von einem RDS-Host
Write-Host "`nAnalysiere Netzwerk-Traffic von <INTERNAL-SERVER>-rds01..." -ForegroundColor Cyan
$trafficResults = Analyze-NetworkTraffic -ServerName "<INTERNAL-SERVER>-rds01"

# Zusammenfassung
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($trafficResults) {
    Write-Host "`nDNS-Test-Ergebnisse:" -ForegroundColor Yellow
    if ($trafficResults.DNSTest) {
        Write-Host "  Abfragen: $($trafficResults.DNSTest.Queries)" -ForegroundColor Green
        Write-Host "  Fehler: $($trafficResults.DNSTest.Errors)" -ForegroundColor $(if ($trafficResults.DNSTest.Errors -gt 0) { "Red" } else { "Green" })
        Write-Host "  Durchschnitt: $($trafficResults.DNSTest.AverageMS) ms" -ForegroundColor $(if ($trafficResults.DNSTest.AverageMS -gt 50) { "Red" } else { "Green" })
        Write-Host "  Min: $($trafficResults.DNSTest.MinMS) ms, Max: $($trafficResults.DNSTest.MaxMS) ms" -ForegroundColor White
    }
    
    Write-Host "`nNetzwerk-Traffic (während Test):" -ForegroundColor Yellow
    if ($trafficResults.TrafficDiff) {
        foreach ($adapter in $trafficResults.TrafficDiff) {
            Write-Host "  $($adapter.Name):" -ForegroundColor Cyan
            Write-Host "    Empfangen: $($adapter.ReceivedBytes) Bytes, $($adapter.ReceivedPackets) Pakete" -ForegroundColor White
            Write-Host "    Gesendet: $($adapter.SentBytes) Bytes, $($adapter.SentPackets) Pakete" -ForegroundColor White
        }
    }
    
    Write-Host "`nTCP-Verbindungen zu Port 53:" -ForegroundColor Yellow
    if ($trafficResults.TCPConnections53) {
        Write-Host "  Anzahl: $($trafficResults.TCPConnections53.Count)" -ForegroundColor Green
    }
    
    Write-Host "`nUDP-Verbindungen zu Port 53:" -ForegroundColor Yellow
    if ($trafficResults.UDPConnections53) {
        Write-Host "  Anzahl: $($trafficResults.UDPConnections53.Count)" -ForegroundColor Green
    }
    
    Write-Host "`nDNS-Client-Cache:" -ForegroundColor Yellow
    if ($trafficResults.CacheStats) {
        Write-Host "  Einträge: $($trafficResults.CacheStats.Count)" -ForegroundColor Green
        if ($trafficResults.CacheStats.ByType) {
            Write-Host "  Nach Typ:" -ForegroundColor Cyan
            $trafficResults.CacheStats.ByType | ForEach-Object {
                Write-Host "    $($_.Type): $($_.Count)" -ForegroundColor White
            }
        }
    }
}

# Speichere Ergebnisse
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TrafficAnalysis = $trafficResults
}

$jsonPath = ".\DNS-Netzwerk-Traffic-Analyse-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Ergebnisse gespeichert ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

Write-Host "`nHINWEIS: Für detaillierte Paket-Analyse sollte ein Wireshark-Trace durchgeführt werden:" -ForegroundColor Yellow
Write-Host "  1. Wireshark auf einem RDS-Host installieren" -ForegroundColor White
Write-Host "  2. Capture-Filter: 'udp.port == 53 or tcp.port == 53'" -ForegroundColor White
Write-Host "  3. Während RDS-Anmeldung mitschneiden" -ForegroundColor White
Write-Host "  4. Verzögerungen zwischen Request und Response analysieren" -ForegroundColor White

$results
