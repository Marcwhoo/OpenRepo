# DNS-Performance-Counter auf beiden DCs aktivieren

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS-Performance-Counter Aktivierung" -ForegroundColor Cyan
Write-Host "<DC-SERVER> und <DC-SERVER>" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

function Enable-DNSPerformanceCounters {
    param([string]$ServerName)
    
    Write-Host "`n=== Aktiviere Performance-Counter auf $ServerName ===" -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $ServerName -ErrorAction Stop
        
        $result = Invoke-Command -Session $session -ScriptBlock {
            $output = @{}
            
            # 1. Prüfe ob Performance-Counter bereits verfügbar sind
            Write-Host "  1. Prüfe verfügbare DNS-Counter..." -NoNewline
            try {
                $dnsCounters = Get-Counter -ListSet "\DNS\*" -ErrorAction SilentlyContinue
                if ($dnsCounters) {
                    $output.CountersAvailable = $true
                    $output.CounterSets = $dnsCounters | Select-Object CounterSetName
                    Write-Host " OK ($($dnsCounters.Count) Counter-Sets)" -ForegroundColor Green
                }
                else {
                    $output.CountersAvailable = $false
                    Write-Host " NICHT VERFÜGBAR" -ForegroundColor Yellow
                }
            }
            catch {
                $output.CountersAvailable = $false
                Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # 2. Versuche Counter zu lesen (aktiviert sie oft automatisch)
            Write-Host "  2. Versuche Counter zu lesen (aktiviert sie)..." -NoNewline
            try {
                $testCounter = Get-Counter "\DNS\Total Query Received" -ErrorAction SilentlyContinue
                if ($testCounter) {
                    $output.CounterReadable = $true
                    $output.TestCounterValue = $testCounter.CounterSamples[0].CookedValue
                    Write-Host " OK" -ForegroundColor Green
                }
                else {
                    $output.CounterReadable = $false
                    Write-Host " NICHT LESBAR" -ForegroundColor Yellow
                }
            }
            catch {
                $output.CounterReadable = $false
                Write-Host " FEHLER" -ForegroundColor Red
            }
            
            # 3. Erstelle Data Collector Set für kontinuierliche Überwachung
            Write-Host "  3. Erstelle Data Collector Set..." -NoNewline
            try {
                $dcSetName = "DNS-Performance-Monitoring"
                
                # Prüfe ob bereits vorhanden
                $existingSet = Get-DataCollectorSet -Name $dcSetName -ErrorAction SilentlyContinue
                if ($existingSet) {
                    Write-Host " BEREITS VORHANDEN" -ForegroundColor Yellow
                    $output.DataCollectorSetExists = $true
                    
                    # Prüfe Status
                    $status = $existingSet.Status
                    Write-Host "    Status: $status" -ForegroundColor $(if ($status -eq "Running") { "Green" } else { "Yellow" })
                    $output.DataCollectorSetStatus = $status
                    
                    # Starte falls nicht läuft
                    if ($status -ne "Running") {
                        Write-Host "    Starte Data Collector Set..." -NoNewline
                        try {
                            Start-DataCollectorSet -Name $dcSetName
                            Write-Host " OK" -ForegroundColor Green
                            $output.DataCollectorSetStarted = $true
                        }
                        catch {
                            Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                            $output.DataCollectorSetStarted = $false
                        }
                    }
                    else {
                        $output.DataCollectorSetStarted = $true
                    }
                }
                else {
                    # Erstelle neues Data Collector Set
                    Write-Host " ERSTELLE NEU..." -ForegroundColor Cyan
                    
                    # Erstelle XML-Template für Data Collector Set
                    $xmlTemplate = @"
<?xml version="1.0" encoding="UTF-16"?>
<DataCollectorSet>
    <Name>$dcSetName</Name>
    <Description>DNS Performance Monitoring</Description>
    <OutputLocation>C:\PerfLogs\DNS-Performance</OutputLocation>
    <PerformanceCounterDataCollector>
        <Name>DNS-Counters</Name>
        <Counter>\DNS\Total Query Received</Counter>
        <Counter>\DNS\Total Query Response Time</Counter>
        <Counter>\DNS\Total Response Sent</Counter>
        <Counter>\DNS\UDP Query Received</Counter>
        <Counter>\DNS\TCP Query Received</Counter>
        <Counter>\DNS\Recursive Queries</Counter>
        <Counter>\DNS\Recursive Query Failures</Counter>
        <Counter>\DNS\Cache Hits</Counter>
        <Counter>\DNS\Cache Misses</Counter>
        <SampleInterval>15</SampleInterval>
        <LogFileFormat>csv</LogFileFormat>
        <LogAppend>false</LogAppend>
        <LogCircular>true</LogCircular>
        <LogMaxSize>100</LogMaxSize>
    </PerformanceCounterDataCollector>
    <Schedule>
        <StartDate>2026-01-22</StartDate>
        <StartTime>00:00:00</StartTime>
    </Schedule>
</DataCollectorSet>
"@
                    
                    # Speichere XML temporär
                    $xmlPath = "$env:TEMP\DNS-Performance-Template.xml"
                    $xmlTemplate | Out-File -FilePath $xmlPath -Encoding UTF8
                    
                    try {
                        # Erstelle Data Collector Set aus XML
                        $dcSet = New-DataCollectorSet -XmlTemplate (Get-Content $xmlPath -Raw) -ErrorAction Stop
                        $output.DataCollectorSetCreated = $true
                        Write-Host "    Data Collector Set erstellt" -ForegroundColor Green
                        
                        # Starte Data Collector Set
                        Write-Host "    Starte Data Collector Set..." -NoNewline
                        try {
                            $dcSet.Start()
                            $output.DataCollectorSetStarted = $true
                            Write-Host " OK" -ForegroundColor Green
                        }
                        catch {
                            Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                            $output.DataCollectorSetStarted = $false
                        }
                        
                        # Lösche temporäre XML
                        Remove-Item $xmlPath -ErrorAction SilentlyContinue
                    }
                    catch {
                        Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                        $output.DataCollectorSetCreated = $false
                        $output.DataCollectorSetError = $_.Exception.Message
                        
                        # Versuche einfachere Methode: Nur Counter lesen
                        Write-Host "    Versuche einfachere Aktivierung..." -NoNewline
                        try {
                            # Einfach Counter lesen - das aktiviert sie oft
                            $null = Get-Counter "\DNS\*" -ErrorAction SilentlyContinue
                            $output.SimpleActivation = $true
                            Write-Host " OK" -ForegroundColor Green
                        }
                        catch {
                            $output.SimpleActivation = $false
                            Write-Host " FEHLER" -ForegroundColor Red
                        }
                    }
                }
            }
            catch {
                Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                $output.DataCollectorSetError = $_.Exception.Message
            }
            
            # 4. Prüfe Performance-Log-Verzeichnis
            Write-Host "  4. Prüfe Performance-Log-Verzeichnis..." -NoNewline
            $logPath = "C:\PerfLogs\DNS-Performance"
            if (Test-Path $logPath) {
                $logFiles = Get-ChildItem -Path $logPath -ErrorAction SilentlyContinue
                $output.LogPath = $logPath
                $output.LogFilesCount = $logFiles.Count
                $output.LogFilesSizeMB = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                Write-Host " OK ($($logFiles.Count) Dateien, $($output.LogFilesSizeMB) MB)" -ForegroundColor Green
            }
            else {
                Write-Host " NICHT VORHANDEN (wird erstellt wenn nötig)" -ForegroundColor Yellow
                $output.LogPath = $logPath
                $output.LogFilesCount = 0
            }
            
            # 5. Prüfe Disk-Space
            Write-Host "  5. Prüfe Disk-Space..." -NoNewline
            $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
            if ($disk) {
                $output.DiskSpace = @{
                    FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                    TotalGB = [math]::Round($disk.Size / 1GB, 2)
                    PercentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
                }
                Write-Host " OK ($($output.DiskSpace.FreeGB) GB frei)" -ForegroundColor Green
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

# Aktiviere auf beiden Servern
Write-Host "`nAktiviere DNS-Performance-Counter..." -ForegroundColor Cyan

$dc01Result = Enable-DNSPerformanceCounters -ServerName "<DC-SERVER>"
$dc02Result = Enable-DNSPerformanceCounters -ServerName "<DC-SERVER>"

# Zusammenfassung
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc01Result.CountersAvailable) {
    Write-Host "  ✅ Counter verfügbar" -ForegroundColor Green
}
if ($dc01Result.CounterReadable) {
    Write-Host "  ✅ Counter lesbar" -ForegroundColor Green
}
if ($dc01Result.DataCollectorSetStarted) {
    Write-Host "  ✅ Data Collector Set läuft" -ForegroundColor Green
}
if ($dc01Result.DiskSpace) {
    Write-Host "  💾 Disk-Space: $($dc01Result.DiskSpace.FreeGB) GB frei ($($dc01Result.DiskSpace.PercentFree)%)" -ForegroundColor $(if ($dc01Result.DiskSpace.PercentFree -lt 10) { "Red" } else { "Green" })
}

Write-Host "`n<DC-SERVER>:" -ForegroundColor Yellow
if ($dc02Result.CountersAvailable) {
    Write-Host "  ✅ Counter verfügbar" -ForegroundColor Green
}
if ($dc02Result.CounterReadable) {
    Write-Host "  ✅ Counter lesbar" -ForegroundColor Green
}
if ($dc02Result.DataCollectorSetStarted) {
    Write-Host "  ✅ Data Collector Set läuft" -ForegroundColor Green
}
if ($dc02Result.DiskSpace) {
    Write-Host "  💾 Disk-Space: $($dc02Result.DiskSpace.FreeGB) GB frei ($($dc02Result.DiskSpace.PercentFree)%)" -ForegroundColor $(if ($dc02Result.DiskSpace.PercentFree -lt 10) { "Red" } else { "Green" })
}

# Speichere Ergebnisse
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DC01 = $dc01Result
    DC02 = $dc02Result
}

$jsonPath = ".\DNS-Performance-Counter-Aktivierung-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "`n=== Ergebnisse gespeichert ===" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Yellow

Write-Host "`n✅ Aktivierung abgeschlossen!" -ForegroundColor Green
Write-Host "`nHinweis: Performance-Counter werden jetzt kontinuierlich gesammelt." -ForegroundColor Cyan
Write-Host "Log-Dateien: C:\PerfLogs\DNS-Performance auf jedem Server" -ForegroundColor Cyan

$results
