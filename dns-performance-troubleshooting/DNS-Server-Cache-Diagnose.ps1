# DNS Server Cache Diagnose
# Analysiert DNS-Server-Cache-Probleme und Konfiguration

param(
    [Parameter(Mandatory=$false)]
    [string[]]$DcNames = @("<DC-SERVER>", "<DC-SERVER>")
)

# Ensure DcNames is an array
if ($DcNames -is [string]) {
    $DcNames = @($DcNames)
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Server Cache Diagnose" -ForegroundColor Cyan
Write-Host "DCs: $($DcNames -join ', ')" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($DcName in $DcNames) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "ANALYSE: $DcName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # 1. DNS-Server-Cache-Status
    Write-Host "1. DNS-SERVER-CACHE STATUS" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    try {
        $cacheInfo = Invoke-Command -ComputerName $DcName -ScriptBlock {
            $cache = Get-DnsServerCache -ErrorAction SilentlyContinue
            return @{
                Count = $cache.Count
                Entries = $cache | Select-Object -First 10 HostName, RecordType, TimeToLive, DataLength
            }
        }
        
        Write-Host "   Cache-Eintraege: $($cacheInfo.Count)" -ForegroundColor $(if ($cacheInfo.Count -eq 0) { "Red" } elseif ($cacheInfo.Count -lt 10) { "Yellow" } else { "Green" })
        
        if ($cacheInfo.Count -eq 0) {
            Write-Host "   WARNING: Cache ist leer!" -ForegroundColor Red
        } elseif ($cacheInfo.Count -lt 10) {
            Write-Host "   WARNING: Cache hat sehr wenige Eintraege!" -ForegroundColor Yellow
        }
        
        if ($cacheInfo.Entries.Count -gt 0) {
            Write-Host ""
            Write-Host "   Beispiel-Eintraege:" -ForegroundColor White
            $cacheInfo.Entries | Format-Table HostName, RecordType, TimeToLive, DataLength -AutoSize
        }
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # 2. DNS-Server-Cache-Konfiguration (Registry)
    Write-Host "2. DNS-SERVER-CACHE KONFIGURATION (Registry)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    try {
        $regSettings = Invoke-Command -ComputerName $DcName -ScriptBlock {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters"
            $settings = @{}
            
            if (Test-Path $regPath) {
                $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                
                # Cache TTL Settings
                $settings.MaxCacheTTL = if ($props.MaxCacheTTL) { "$($props.MaxCacheTTL) seconds ($([math]::Round($props.MaxCacheTTL / 3600, 2)) hours)" } else { "Not set (default: 86,400s = 24h)" }
                $settings.MaxNegativeCacheTTL = if ($props.MaxNegativeCacheTTL) { "$($props.MaxNegativeCacheTTL) seconds ($([math]::Round($props.MaxNegativeCacheTTL / 60, 2)) minutes)" } else { "Not set (default: 900s = 15min)" }
                
                # Cache Size Settings
                $settings.CacheHashTableBucketSize = if ($props.CacheHashTableBucketSize) { $props.CacheHashTableBucketSize } else { "Not set (default)" }
                $settings.CacheHashTableSize = if ($props.CacheHashTableSize) { $props.CacheHashTableSize } else { "Not set (default)" }
                
                # Other cache-related settings
                $settings.EnableDirectoryPartitions = if ($props.EnableDirectoryPartitions) { $props.EnableDirectoryPartitions } else { "Not set" }
                $settings.DisableAutoReverseZones = if ($props.DisableAutoReverseZones) { $props.DisableAutoReverseZones } else { "Not set" }
            }
            
            return $settings
        }
        
        Write-Host "   MaxCacheTTL: $($regSettings.MaxCacheTTL)" -ForegroundColor White
        Write-Host "   MaxNegativeCacheTTL: $($regSettings.MaxNegativeCacheTTL)" -ForegroundColor White
        Write-Host "   CacheHashTableBucketSize: $($regSettings.CacheHashTableBucketSize)" -ForegroundColor White
        Write-Host "   CacheHashTableSize: $($regSettings.CacheHashTableSize)" -ForegroundColor White
        
        # Analyse
        if ($regSettings.MaxCacheTTL -like "*Not set*") {
            Write-Host "   INFO: MaxCacheTTL nicht gesetzt - verwendet Standard (24h)" -ForegroundColor Gray
        }
        if ($regSettings.MaxNegativeCacheTTL -like "*Not set*") {
            Write-Host "   INFO: MaxNegativeCacheTTL nicht gesetzt - verwendet Standard (15min)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # 3. DNS-Server-Settings (PowerShell)
    Write-Host "3. DNS-SERVER-SETTINGS (PowerShell)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    try {
        $dnsSettings = Invoke-Command -ComputerName $DcName -ScriptBlock {
            Get-DnsServerSetting -All | Where-Object { 
                $_.Name -like "*Cache*" -or 
                $_.Name -like "*TTL*" -or
                $_.Name -like "*Scavenging*" -or
                $_.Name -like "*Forwarder*"
            } | Select-Object Name, Value, Description
        }
        
        if ($dnsSettings) {
            $dnsSettings | Format-Table Name, Value, Description -AutoSize
        } else {
            Write-Host "   Keine spezifischen Cache-Settings gefunden" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # 4. Cache-Verhalten testen
    Write-Host "4. CACHE-VERHALTEN TEST" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    try {
        $cacheTest = Invoke-Command -ComputerName $DcName -ScriptBlock {
            # Cache vorher
            $cacheBefore = (Get-DnsServerCache).Count
            
            # Externe Query durchführen
            $testDomain = "google.com"
            Resolve-DnsName -Name $testDomain -Server localhost -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 1
            
            # Cache nachher
            $cacheAfter = (Get-DnsServerCache).Count
            $cacheDiff = $cacheAfter - $cacheBefore
            
            # Prüfe ob der Eintrag im Cache ist
            $cacheEntry = Get-DnsServerCache | Where-Object { $_.HostName -like "*$testDomain*" } | Select-Object -First 1
            
            return @{
                CacheBefore = $cacheBefore
                CacheAfter = $cacheAfter
                CacheDiff = $cacheDiff
                TestDomain = $testDomain
                EntryFound = ($cacheEntry -ne $null)
                CacheEntry = $cacheEntry
            }
        }
        
        Write-Host "   Cache vor Query: $($cacheTest.CacheBefore)" -ForegroundColor White
        Write-Host "   Cache nach Query: $($cacheTest.CacheAfter)" -ForegroundColor White
        Write-Host "   Differenz: $($cacheTest.CacheDiff)" -ForegroundColor $(if ($cacheTest.CacheDiff -gt 0) { "Green" } else { "Red" })
        
        if ($cacheTest.EntryFound) {
            Write-Host "   Test-Domain '$($cacheTest.TestDomain)' im Cache gefunden: OK" -ForegroundColor Green
            if ($cacheTest.CacheEntry) {
                Write-Host "   - HostName: $($cacheTest.CacheEntry.HostName)" -ForegroundColor Gray
                Write-Host "   - RecordType: $($cacheTest.CacheEntry.RecordType)" -ForegroundColor Gray
                Write-Host "   - TTL: $($cacheTest.CacheEntry.TimeToLive)" -ForegroundColor Gray
            }
        } else {
            Write-Host "   WARNING: Test-Domain '$($cacheTest.TestDomain)' NICHT im Cache!" -ForegroundColor Red
            Write-Host "   PROBLEM: Cache funktioniert nicht richtig!" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # 5. Cache-Statistiken (Performance Counter)
    Write-Host "5. CACHE-STATISTIKEN (Performance Counter)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    try {
        $perfCounters = Invoke-Command -ComputerName $DcName -ScriptBlock {
            $counters = @{}
            
            # DNS Cache Statistics
            $counterNames = @(
                "DNS\Total Query Received",
                "DNS\Total Response Sent",
                "DNS\Total Query Received/sec",
                "DNS\Total Response Sent/sec"
            )
            
            foreach ($counterName in $counterNames) {
                try {
                    $counter = Get-Counter -Counter $counterName -ErrorAction SilentlyContinue
                    if ($counter) {
                        $counters[$counterName] = $counter.CounterSamples[0].CookedValue
                    }
                }
                catch {
                    # Counter nicht verfügbar
                }
            }
            
            return $counters
        }
        
        if ($perfCounters.Count -gt 0) {
            foreach ($key in $perfCounters.Keys) {
                Write-Host "   $key : $($perfCounters[$key])" -ForegroundColor White
            }
        } else {
            Write-Host "   Performance Counter nicht verfügbar" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    
    # 6. Cache-Probleme identifizieren
    Write-Host "6. PROBLEM-IDENTIFIZIERUNG" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    $problems = @()
    
    # Problem 1: Cache ist leer
    if ($cacheInfo.Count -eq 0) {
        $problems += "Cache ist leer - keine Eintraege vorhanden"
    }
    
    # Problem 2: Cache wird nicht verwendet
    if ($cacheTest.CacheDiff -eq 0 -or -not $cacheTest.EntryFound) {
        $problems += "Cache wird nicht verwendet - neue Queries werden nicht gecacht"
    }
    
    # Problem 3: Cache hat sehr wenige Eintraege
    if ($cacheInfo.Count -lt 10 -and $cacheInfo.Count -gt 0) {
        $problems += "Cache hat sehr wenige Eintraege ($($cacheInfo.Count)) - moeglicherweise wird Cache zu haeufig geleert"
    }
    
    if ($problems.Count -gt 0) {
        Write-Host "   Gefundene Probleme:" -ForegroundColor Red
        foreach ($problem in $problems) {
            Write-Host "   - $problem" -ForegroundColor Red
        }
    } else {
        Write-Host "   Keine offensichtlichen Probleme gefunden" -ForegroundColor Green
    }
    Write-Host ""
    
    # 7. Empfehlungen
    Write-Host "7. EMPFEHLUNGEN" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    $recommendations = @()
    
    if ($cacheInfo.Count -eq 0) {
        $recommendations += "Cache ist leer - pruefe DNS-Service-Status und Event-Logs"
        $recommendations += "Versuche Cache manuell zu leeren: Clear-DnsServerCache -Force"
    }
    
    if ($cacheTest.CacheDiff -eq 0 -or -not $cacheTest.EntryFound) {
        $recommendations += "Cache funktioniert nicht - pruefe DNS-Service-Konfiguration"
        $recommendations += "Pruefe ob Forwarder korrekt konfiguriert sind"
        $recommendations += "Pruefe Event-Logs auf DNS-Fehler"
    }
    
    if ($regSettings.MaxCacheTTL -like "*Not set*") {
        $recommendations += "MaxCacheTTL nicht gesetzt - Standard (24h) wird verwendet (OK)"
    }
    
    if ($recommendations.Count -gt 0) {
        foreach ($rec in $recommendations) {
            Write-Host "   - $rec" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   Keine spezifischen Empfehlungen" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host ""
}

# Vergleich zwischen DCs
if ($DcNames.Count -gt 1) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "VERGLEICH ZWISCHEN DCs" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $comparison = @()
    foreach ($DcName in $DcNames) {
        $cacheCount = Invoke-Command -ComputerName $DcName -ScriptBlock {
            (Get-DnsServerCache).Count
        }
        $comparison += [PSCustomObject]@{
            DC = $DcName
            CacheEntries = $cacheCount
        }
    }
    
    $comparison | Format-Table DC, CacheEntries -AutoSize
    
    $maxDiff = ($comparison | Measure-Object -Property CacheEntries -Maximum).Maximum - ($comparison | Measure-Object -Property CacheEntries -Minimum).Minimum
    if ($maxDiff -gt 100) {
        Write-Host "WARNING: Großer Unterschied zwischen DCs ($maxDiff Eintraege)" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Diagnose abgeschlossen!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
