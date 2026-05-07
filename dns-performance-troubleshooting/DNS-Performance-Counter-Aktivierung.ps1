# DNS-Performance-Counter prüfen und Anleitung zur Aktivierung

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS-Performance-Counter-Prüfung" -ForegroundColor Cyan
Write-Host "NUR LESEN - KEINE AENDERUNGEN!" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

function Check-DNSPerformanceCounters {
    param([string]$ServerName)
    
    Write-Host "`n=== Prüfe Performance-Counter auf $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $data = Invoke-Command -Session $session -ScriptBlock {
            $result = @{}
            
            # 1. Verfügbare DNS-Performance-Counter prüfen
            Write-Host "  1. Prüfe verfügbare DNS-Counter..." -NoNewline
            $availableCounters = @()
            $counterNames = @(
                "\DNS\Total Query Received",
                "\DNS\Total Query Response Time",
                "\DNS\Total Response Sent",
                "\DNS\UDP Query Received",
                "\DNS\TCP Query Received",
                "\DNS\Recursive Queries",
                "\DNS\Recursive Query Failures",
                "\DNS\Dynamic Updates Received",
                "\DNS\Secure Update Requests",
                "\DNS\AXFR Requests Received",
                "\DNS\IXFR Requests Received",
                "\DNS\Cache Hits",
                "\DNS\Cache Misses"
            )
            
            foreach ($counterName in $counterNames) {
                try {
                    $counter = Get-Counter -ListSet $counterName -ErrorAction SilentlyContinue
                    if ($counter) {
                        $availableCounters += $counterName
                    }
                }
                catch {
                    # Counter nicht verfügbar
                }
            }
            
            $result.AvailableCounters = $availableCounters
            Write-Host " OK ($($availableCounters.Count) Counter verfügbar)" -ForegroundColor $(if ($availableCounters.Count -gt 0) { "Green" } else { "Yellow" })
            
            # 2. Versuche Counter-Werte zu lesen
            Write-Host "  2. Versuche Counter-Werte zu lesen..." -NoNewline
            $counterValues = @{}
            foreach ($counterName in $availableCounters) {
                try {
                    $counter = Get-Counter $counterName -ErrorAction SilentlyContinue
                    if ($counter) {
                        $counterValues[$counterName] = $counter.CounterSamples[0].CookedValue
                    }
                }
                catch {
                    # Wert kann nicht gelesen werden
                }
            }
            $result.CounterValues = $counterValues
            Write-Host " OK ($($counterValues.Count) Werte gelesen)" -ForegroundColor Green
            
            # 3. Prüfe ob Performance-Counter aktiviert sind
            Write-Host "  3. Prüfe Counter-Aktivierung..." -NoNewline
            $result.CountersEnabled = $availableCounters.Count -gt 0
            Write-Host " $(if ($result.CountersEnabled) { 'AKTIVIERT' } else { 'NICHT AKTIVIERT' })" -ForegroundColor $(if ($result.CountersEnabled) { "Green" } else { "Yellow" })
            
            # 4. Prüfe DNS-Service-Status
            Write-Host "  4. DNS-Service-Status..." -NoNewline
            $dnsService = Get-Service DNS -ErrorAction SilentlyContinue
            $result.DNSService = @{
                Status = $dnsService.Status
                StartType = $dnsService.StartType
            }
            Write-Host " OK ($($dnsService.Status))" -ForegroundColor Green
            
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

# Prüfe beide Server
$dc01Counters = Check-DNSPerformanceCounters -ServerName "<DC-SERVER>"
$dc02Counters = Check-DNSPerformanceCounters -ServerName "<DC-SERVER>"

# Vergleich
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VERGLEICH" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($dc01Counters -and $dc02Counters) {
    Write-Host "`nPerformance-Counter-Status:" -ForegroundColor Yellow
    Write-Host "  <DC-SERVER>: $(if ($dc01Counters.CountersEnabled) { 'AKTIVIERT' } else { 'NICHT AKTIVIERT' }) ($($dc01Counters.AvailableCounters.Count) Counter)" -ForegroundColor $(if ($dc01Counters.CountersEnabled) { "Green" } else { "Yellow" })
    Write-Host "  <DC-SERVER>: $(if ($dc02Counters.CountersEnabled) { 'AKTIVIERT' } else { 'NICHT AKTIVIERT' }) ($($dc02Counters.AvailableCounters.Count) Counter)" -ForegroundColor $(if ($dc02Counters.CountersEnabled) { "Green" } else { "Yellow" })
    
    if (-not $dc01Counters.CountersEnabled -or -not $dc02Counters.CountersEnabled) {
        Write-Host "`n⚠️ WARNUNG: Performance-Counter sind nicht aktiviert!" -ForegroundColor Red
        Write-Host "  Für kontinuierliche Überwachung müssen die Counter aktiviert werden." -ForegroundColor Yellow
        Write-Host "`n  Aktivierung (manuell erforderlich):" -ForegroundColor Cyan
        Write-Host "    1. Performance Monitor (perfmon.exe) öffnen" -ForegroundColor White
        Write-Host "    2. Data Collector Sets → User Defined → Neu erstellen" -ForegroundColor White
        Write-Host "    3. Performance Counter hinzufügen" -ForegroundColor White
        Write-Host "    4. DNS-Counter auswählen (z.B. \DNS\Total Query Received)" -ForegroundColor White
        Write-Host "    5. Oder per PowerShell: Get-Counter '\DNS\*'" -ForegroundColor White
    }
    
    # Zeige verfügbare Counter
    if ($dc01Counters.AvailableCounters.Count -gt 0) {
        Write-Host "`nVerfügbare DNS-Counter:" -ForegroundColor Yellow
        $dc01Counters.AvailableCounters | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor White
        }
    }
}

# Speichere Ergebnisse
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DC01 = $dc01Counters
    DC02 = $dc02Counters
}

$jsonPath = ".\DNS-Performance-Counter-Prüfung-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Ergebnisse gespeichert ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

$results
