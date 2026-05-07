# DNS-Abfrage-Quellen identifizieren (über DNS-Analytic-Logs)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS-Abfrage-Quellen Analyse" -ForegroundColor Cyan
Write-Host "<DC-SERVER>" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n⚠️ HINWEIS: Query-Source-Analyse läuft NICHT über logman!" -ForegroundColor Yellow
Write-Host "Dieses Script verwendet DNS-Analytic-Logs (Event-Logs)." -ForegroundColor Cyan
Write-Host "Analytic-Logs können sehr groß werden (mehrere GB pro Tag bei hohem Traffic)." -ForegroundColor Yellow
Write-Host ""

function Analyze-DNSQuerySources {
    param([string]$ServerName)
    
    Write-Host "`n=== Analysiere DNS-Abfrage-Quellen auf $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $result = Invoke-Command -Session $session -ScriptBlock {
            $output = @{}
            
            # 1. Prüfe DNS-Analytic-Logs Status
            Write-Host "  1. Prüfe DNS-Analytic-Logs Status..." -NoNewline
            try {
                $analyticLogStatus = wevtutil gl "Microsoft-Windows-DNS-Server-Analytic/Operational" 2>&1
                if ($analyticLogStatus -match "enabled:\s*true") {
                    $output.AnalyticLogEnabled = $true
                    Write-Host " AKTIVIERT" -ForegroundColor Green
                }
                else {
                    $output.AnalyticLogEnabled = $false
                    Write-Host " NICHT AKTIVIERT" -ForegroundColor Yellow
                    Write-Host "    Hinweis: Analytic-Logs müssen aktiviert werden für Query-Source-Analyse" -ForegroundColor Cyan
                }
            }
            catch {
                $output.AnalyticLogEnabled = $false
                Write-Host " FEHLER" -ForegroundColor Red
                $output.AnalyticLogError = $_.Exception.Message
            }
            
            # 2. Aktive DNS-Verbindungen prüfen (Netstat)
            Write-Host "  2. Prüfe aktive DNS-Verbindungen (Netstat)..." -NoNewline
            try {
                $netstatOutput = netstat -ano | Select-String ":53"
                $connections = $netstatOutput | ForEach-Object {
                    if ($_ -match '(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)') {
                        [PSCustomObject]@{
                            Protocol = $matches[1]
                            LocalAddress = $matches[2]
                            ForeignAddress = $matches[3]
                            State = $matches[4]
                            PID = $matches[5]
                        }
                    }
                }
                
                $output.ActiveConnections = $connections
                Write-Host " OK ($($connections.Count) Verbindungen)" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $output.ConnectionsError = $_.Exception.Message
            }
            
            # 3. DNS-Server-Statistiken
            Write-Host "  3. Prüfe DNS-Server-Statistiken..." -NoNewline
            try {
                $dnsStats = Get-DnsServerStatistics -ErrorAction SilentlyContinue
                
                if ($dnsStats) {
                    $output.DNSStatistics = $dnsStats
                    Write-Host " OK" -ForegroundColor Green
                }
                else {
                    Write-Host " NICHT VERFÜGBAR" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $output.StatsError = $_.Exception.Message
            }
            
            # 4. DNS-Event-Logs prüfen (letzte 24 Stunden) - wenn Analytic-Logs aktiviert
            if ($output.AnalyticLogEnabled) {
                Write-Host "  4. Analysiere DNS-Analytic-Logs (letzte 24h)..." -NoNewline
                try {
                    $events = Get-WinEvent -FilterHashtable @{
                        LogName = "Microsoft-Windows-DNS-Server-Analytic/Operational"
                        StartTime = (Get-Date).AddHours(-24)
                    } -ErrorAction SilentlyContinue -MaxEvents 10000
                    
                    if ($events) {
                        # Analysiere Events nach Client-IPs
                        $clientIPs = $events | ForEach-Object {
                            $xml = [xml]$_.ToXml()
                            $clientIP = $xml.Event.EventData.Data | Where-Object { $_.Name -eq "ClientIp" -or $_.Name -eq "ClientIP" } | Select-Object -ExpandProperty "#text" -First 1
                            if ($clientIP) {
                                [PSCustomObject]@{
                                    ClientIP = $clientIP
                                    TimeCreated = $_.TimeCreated
                                    Id = $_.Id
                                }
                            }
                        } | Where-Object { $_.ClientIP } | Group-Object ClientIP | Sort-Object Count -Descending | Select-Object -First 20
                        
                        $output.TopClients = $clientIPs
                        Write-Host " OK ($($events.Count) Events, $($clientIPs.Count) verschiedene Clients)" -ForegroundColor Green
                    }
                    else {
                        Write-Host " KEINE EVENTS" -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host " FEHLER" -ForegroundColor Red
                    $output.EventsError = $_.Exception.Message
                }
            }
            else {
                Write-Host "  4. Überspringe Event-Log-Analyse (Analytic-Logs nicht aktiviert)" -ForegroundColor Yellow
            }
            
            # 5. DNS-Cache-Analyse (welche Domains werden am häufigsten abgefragt)
            Write-Host "  5. Prüfe DNS-Cache (Top Domains)..." -NoNewline
            try {
                $cache = Get-DnsServerCache -ErrorAction SilentlyContinue
                
                if ($cache) {
                    # Gruppiere nach Domain
                    $topDomains = $cache | Group-Object HostName | Sort-Object Count -Descending | Select-Object -First 20
                    $output.TopDomains = $topDomains
                    Write-Host " OK ($($cache.Count) Einträge, $($topDomains.Count) verschiedene Domains)" -ForegroundColor Green
                }
                else {
                    Write-Host " NICHT VERFÜGBAR" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $output.CacheError = $_.Exception.Message
            }
            
            # 6. Netzwerk-Traffic-Analyse (TCP-Verbindungen zu Port 53)
            Write-Host "  6. Prüfe TCP-Verbindungen zu Port 53..." -NoNewline
            try {
                $tcpConnections = Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue | 
                    Select-Object LocalAddress, RemoteAddress, State, OwningProcess
                
                $output.TCPConnections = $tcpConnections
                Write-Host " OK ($($tcpConnections.Count) TCP-Verbindungen)" -ForegroundColor Green
            }
            catch {
                Write-Host " FEHLER" -ForegroundColor Red
                $output.TCPError = $_.Exception.Message
            }
            
            return $output
        }
        
        Remove-PSSession $session
        return $result
    }
    catch {
        Write-Warning "Fehler bei $ServerName : $($_.Exception.Message)"
        return @{ Error = $_.Exception.Message }
    }
}

# Analysiere <DC-SERVER>
$result = Analyze-DNSQuerySources -ServerName "<DC-SERVER>"

# Ausgabe
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ERGEBNISSE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($result.TopClients) {
    Write-Host "`nTop 20 DNS-Clients (nach Analytic-Logs):" -ForegroundColor Yellow
    $counter = 1
    foreach ($client in $result.TopClients) {
        Write-Host "$counter. $($client.Name): $($client.Count) Abfragen" -ForegroundColor Green
        $counter++
    }
}
else {
    Write-Host "`n⚠️ Keine Client-Daten verfügbar (Analytic-Logs nicht aktiviert oder keine Events)" -ForegroundColor Yellow
}

if ($result.TopDomains) {
    Write-Host "`nTop 20 abgefragte Domains (DNS-Cache):" -ForegroundColor Yellow
    $counter = 1
    foreach ($domain in $result.TopDomains) {
        Write-Host "$counter. $($domain.Name): $($domain.Count) Cache-Einträge" -ForegroundColor Green
        $counter++
    }
}

if ($result.ActiveConnections) {
    Write-Host "`nAktive DNS-Verbindungen (Netstat):" -ForegroundColor Yellow
    $result.ActiveConnections | Select-Object -First 10 | Format-Table -AutoSize
}

# Speichere Ergebnisse
$jsonPath = ".\DNS-Query-Source-Analyse-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$result | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Ergebnisse gespeichert ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

if (-not $result.AnalyticLogEnabled) {
    Write-Host "`n⚠️ WICHTIG: Für detaillierte Query-Source-Analyse müssen DNS-Analytic-Logs aktiviert werden:" -ForegroundColor Yellow
    Write-Host "  wevtutil sl Microsoft-Windows-DNS-Server-Analytic/Operational /e:true" -ForegroundColor White
    Write-Host "`n⚠️ WARNUNG: Analytic-Logs können SEHR groß werden (mehrere GB pro Tag bei hohem Traffic)!" -ForegroundColor Red
    Write-Host "  Regelmäßig prüfen und bei Bedarf deaktivieren:" -ForegroundColor Yellow
    Write-Host "  wevtutil sl Microsoft-Windows-DNS-Server-Analytic/Operational /e:false" -ForegroundColor White
}

$result
