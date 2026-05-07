# DNS Extended Analysis
# Tests that can be run while Wireshark analysis is running

param(
    [string]$DcName = "<DC-SERVER>",
    [string]$DcName2 = "<DC-SERVER>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Extended Analysis" -ForegroundColor Cyan
Write-Host "DC1: $DcName | DC2: $DcName2" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. DC Comparison - Why is DC02 faster?
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. DC COMPARISON (DC01 vs DC02)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Testing DNS resolution performance on both DCs..." -ForegroundColor Yellow
$testDomains = @("<DOMAIN-FQDN>", "<DC-SERVER>.<DOMAIN-FQDN>", "<DC-SERVER>.<DOMAIN-FQDN>")

foreach ($domain in $testDomains) {
    Write-Host ""
    Write-Host "Domain: $domain" -ForegroundColor Yellow
    
    # Test on DC01
    $dc01Times = @()
    for ($i = 1; $i -le 10; $i++) {
        $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($d)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Resolve-DnsName -Name $d -ErrorAction SilentlyContinue | Out-Null
            } catch {}
            $sw.Stop()
            return $sw.ElapsedMilliseconds
        } -ArgumentList $domain
        $dc01Times += $result
    }
    $dc01Avg = ($dc01Times | Measure-Object -Average).Average
    $dc01Max = ($dc01Times | Measure-Object -Maximum).Maximum
    
    # Test on DC02
    $dc02Times = @()
    for ($i = 1; $i -le 10; $i++) {
        $result = Invoke-Command -ComputerName $DcName2 -ScriptBlock {
            param($d)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Resolve-DnsName -Name $d -ErrorAction SilentlyContinue | Out-Null
            } catch {}
            $sw.Stop()
            return $sw.ElapsedMilliseconds
        } -ArgumentList $domain
        $dc02Times += $result
    }
    $dc02Max = ($dc02Times | Measure-Object -Maximum).Maximum
    $dc02Avg = ($dc02Times | Measure-Object -Average).Average
    
    Write-Host "  ${DcName}: Avg $([math]::Round($dc01Avg, 2))ms, Max $([math]::Round($dc01Max, 2))ms" -ForegroundColor $(if ($dc01Avg -gt 50) { "Red" } else { "White" })
    Write-Host "  ${DcName2}: Avg $([math]::Round($dc02Avg, 2))ms, Max $([math]::Round($dc02Max, 2))ms" -ForegroundColor $(if ($dc02Avg -gt 50) { "Red" } else { "Green" })
    $diff = $dc01Avg - $dc02Avg
    if ($diff -gt 10) {
        Write-Host "  DIFFERENCE: DC01 is $([math]::Round($diff, 2))ms slower!" -ForegroundColor Red
    }
}

# 2. DNS Scavenging Configuration
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. DNS SCAVENGING CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $scavenging = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        if ($zone) {
            return @{
                ScavengingEnabled = $zone.AgingEnabled
                RefreshInterval = $zone.RefreshInterval
                NoRefreshInterval = $zone.NoRefreshInterval
            }
        }
        return $null
    }
    
    if ($scavenging) {
        Write-Host "Scavenging Enabled: $($scavenging.ScavengingEnabled)" -ForegroundColor White
        Write-Host "Refresh Interval: $($scavenging.RefreshInterval) hours" -ForegroundColor White
        Write-Host "No Refresh Interval: $($scavenging.NoRefreshInterval) hours" -ForegroundColor White
        
        if (-not $scavenging.ScavengingEnabled) {
            Write-Host "WARNING: Scavenging is disabled - old records may accumulate!" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not retrieve scavenging configuration" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. DNS Zone Replication Status
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. DNS ZONE REPLICATION STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $replication = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        if ($zone) {
            return @{
                ZoneType = $zone.ZoneType
                ReplicationScope = $zone.ReplicationScope
                DirectoryPartitionName = $zone.DirectoryPartitionName
            }
        }
        return $null
    }
    
    if ($replication) {
        Write-Host "Zone Type: $($replication.ZoneType)" -ForegroundColor White
        Write-Host "Replication Scope: $($replication.ReplicationScope)" -ForegroundColor White
        Write-Host "Directory Partition: $($replication.DirectoryPartitionName)" -ForegroundColor White
        
        if ($replication.ZoneType -eq "Primary" -and $replication.ReplicationScope -eq "Domain") {
            Write-Host "Zone is AD-integrated and replicates to all DCs in domain" -ForegroundColor Green
        }
    } else {
        Write-Host "Could not retrieve replication information" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. DNS Event Logs - Errors and Warnings
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. DNS EVENT LOGS (Last 24h)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $events = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $startTime = (Get-Date).AddHours(-24)
        Get-WinEvent -FilterHashtable @{
            LogName = "System"
            ProviderName = "Microsoft-Windows-DNS-Server"
            StartTime = $startTime
            Level = 2,3
        } -ErrorAction SilentlyContinue | Select-Object -First 20 TimeCreated, Id, LevelDisplayName, Message
    }
    
    if ($events) {
        Write-Host "Found $($events.Count) DNS errors/warnings in last 24h:" -ForegroundColor Yellow
        foreach ($event in $events) {
            $color = if ($event.LevelDisplayName -eq "Error") { "Red" } else { "Yellow" }
            Write-Host "  [$($event.TimeCreated)] [$($event.LevelDisplayName)] ID $($event.Id): $($event.Message.Substring(0, [Math]::Min(100, $event.Message.Length)))..." -ForegroundColor $color
        }
    } else {
        Write-Host "No DNS errors/warnings found in last 24h" -ForegroundColor Green
    }
} catch {
    Write-Host "Could not retrieve DNS event logs: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 5. DNS Service Uptime Check
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. DNS SERVICE UPTIME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $serviceInfo = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $service = Get-Service -Name DNS
        $process = Get-Process -Name dns -ErrorAction SilentlyContinue
        
        $uptime = $null
        if ($process) {
            $uptime = (Get-Date) - $process.StartTime
        }
        
        return @{
            Status = $service.Status
            StartType = $service.StartType
            UptimeDays = if ($uptime) { [math]::Round($uptime.TotalDays, 2) } else { $null }
            UptimeHours = if ($uptime) { [math]::Round($uptime.TotalHours, 2) } else { $null }
        }
    }
    
    if ($serviceInfo) {
        Write-Host "Service Status: $($serviceInfo.Status)" -ForegroundColor White
        Write-Host "Start Type: $($serviceInfo.StartType)" -ForegroundColor White
        if ($serviceInfo.UptimeDays) {
            Write-Host "Service Uptime: $($serviceInfo.UptimeDays) days ($($serviceInfo.UptimeHours) hours)" -ForegroundColor White
            if ($serviceInfo.UptimeDays -gt 30) {
                Write-Host "WARNING: Service has been running for $($serviceInfo.UptimeDays) days - long uptime may correlate with performance degradation" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Could not determine service uptime" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "ERROR: Could not retrieve service information: $($_.Exception.Message)" -ForegroundColor Red
}

# 6. AD Database Fragmentation Check
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. AD DATABASE FRAGMENTATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $fragInfo = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $ntdsPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters")."DSA Database file"
        $dbPath = $ntdsPath -replace "\\\\.*", ""
        $dbFile = Get-Item $dbPath -ErrorAction SilentlyContinue
        
        if ($dbFile) {
            $fileSize = $dbFile.Length
            $drive = $dbFile.Drive
            $driveInfo = Get-PSDrive $drive.Name
            
            $fragPercent = 0
            try {
                $defragInfo = defrag.exe $drive.Name /A 2>&1 | Select-String "Total fragmentation"
                if ($defragInfo) {
                    $fragPercent = [int]($defragInfo -replace "[^0-9]", "")
                }
            } catch {}
            
            return @{
                DatabaseSizeMB = [math]::Round($fileSize / 1MB, 2)
                DriveFreeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
                DriveFragmentation = $fragPercent
            }
        }
        return $null
    }
    
    if ($fragInfo) {
        Write-Host "Database Size: $($fragInfo.DatabaseSizeMB) MB" -ForegroundColor White
        Write-Host "Drive Free Space: $($fragInfo.DriveFreeSpaceGB) GB" -ForegroundColor White
        Write-Host "Drive Fragmentation: $($fragInfo.DriveFragmentation)%" -ForegroundColor $(if ($fragInfo.DriveFragmentation -gt 10) { "Yellow" } else { "Green" })
        
        if ($fragInfo.DriveFragmentation -gt 10) {
            Write-Host "WARNING: Drive fragmentation is high - may impact AD/DNS performance" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not retrieve fragmentation information" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 7. DNS Zone Statistics Comparison
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "7. DNS ZONE STATISTICS COMPARISON" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    $zone1 = Invoke-Command -ComputerName $DcName -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        if ($zone) {
            $records = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
            return @{
                RecordCount = $records.Count
                ZoneType = $zone.ZoneType
            }
        }
        return $null
    }
    
    $zone2 = Invoke-Command -ComputerName $DcName2 -ScriptBlock {
        $zone = Get-DnsServerZone -Name "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
        if ($zone) {
            $records = Get-DnsServerResourceRecord -ZoneName "<DOMAIN-FQDN>" -ErrorAction SilentlyContinue
            return @{
                RecordCount = $records.Count
                ZoneType = $zone.ZoneType
            }
        }
        return $null
    }
    
    if ($zone1 -and $zone2) {
        Write-Host "${DcName}: $($zone1.RecordCount) records, Type: $($zone1.ZoneType)" -ForegroundColor White
        Write-Host "${DcName2}: $($zone2.RecordCount) records, Type: $($zone2.ZoneType)" -ForegroundColor White
        
        if ($zone1.RecordCount -ne $zone2.RecordCount) {
            $diff = [Math]::Abs($zone1.RecordCount - $zone2.RecordCount)
            Write-Host "WARNING: Record count differs by $diff records!" -ForegroundColor Red
        } else {
            Write-Host "Zone replication appears synchronized" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
