# DNS Zone Analysis Script
# Analyzes DNS zone for problems - READ ONLY, no changes

param(
    [string]$DcName = "<DC-SERVER>",
    [string]$ZoneName = "<DOMAIN-FQDN>"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Zone Analysis" -ForegroundColor Cyan
Write-Host "Domain Controller: $DcName" -ForegroundColor Yellow
Write-Host "Zone: $ZoneName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Zone Overview
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. ZONE OVERVIEW" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
try {
    $zone = Invoke-Command -ComputerName $DcName -ScriptBlock {
        param($zn)
        Get-DnsServerZone -Name $zn
    } -ArgumentList $ZoneName
    
    Write-Host "Zone Name: $($zone.ZoneName)" -ForegroundColor White
    Write-Host "Zone Type: $($zone.ZoneType)" -ForegroundColor White
    Write-Host "Dynamic Update: $($zone.DynamicUpdate)" -ForegroundColor White
    Write-Host "Aging: $($zone.Aging)" -ForegroundColor White
    Write-Host "Paused: $($zone.Paused)" -ForegroundColor White
    Write-Host "Loaded: $($zone.Loaded)" -ForegroundColor White
}
catch {
    Write-Host "ERROR: Could not get zone information: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 2. Get All Records
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "2. LOADING ZONE RECORDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Loading all records from zone..." -NoNewline
try {
    $allRecords = Invoke-Command -ComputerName $DcName -ScriptBlock {
        param($zn)
        Get-DnsServerResourceRecord -ZoneName $zn
    } -ArgumentList $ZoneName
    Write-Host " OK ($($allRecords.Count) records)" -ForegroundColor Green
}
catch {
    Write-Host " ERROR" -ForegroundColor Red
    Write-Host "ERROR: Could not load records: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 3. Record Statistics
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "3. RECORD STATISTICS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$recordStats = $allRecords | Group-Object RecordType | ForEach-Object {
    [PSCustomObject]@{
        RecordType = $_.Name
        Count = $_.Count
        Percentage = [math]::Round(($_.Count / $allRecords.Count) * 100, 2)
    }
} | Sort-Object Count -Descending

Write-Host "Records by Type:" -ForegroundColor Yellow
$recordStats | Format-Table -AutoSize

Write-Host "Total Records: $($allRecords.Count)" -ForegroundColor White
Write-Host ""

# 4. Duplicate Records Analysis
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "4. DUPLICATE RECORDS ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Group by HostName and RecordType to find duplicates
$duplicates = $allRecords | Group-Object @{Expression={$_.HostName}}, @{Expression={$_.RecordType}} | 
    Where-Object { $_.Count -gt 1 } | 
    Sort-Object Count -Descending

if ($duplicates.Count -gt 0) {
    Write-Host "Found $($duplicates.Count) duplicate record groups:" -ForegroundColor Yellow
    Write-Host ""
    
    $duplicateSummary = $duplicates | ForEach-Object {
        $firstRecord = $_.Group[0]
        $recordData = @()
        foreach ($rec in $_.Group) {
            if ($rec.RecordData.IPv4Address) {
                $recordData += $rec.RecordData.IPv4Address.ToString()
            }
            elseif ($rec.RecordData.IPv6Address) {
                $recordData += $rec.RecordData.IPv6Address.ToString()
            }
            elseif ($rec.RecordData.NameServer) {
                $recordData += $rec.RecordData.NameServer
            }
            else {
                $recordData += $rec.RecordData.ToString()
            }
        }
        
        [PSCustomObject]@{
            HostName = $firstRecord.HostName
            RecordType = $firstRecord.RecordType
            DuplicateCount = $_.Count
            Values = ($recordData -join ", ")
        }
    } | Select-Object -First 20
    
    $duplicateSummary | Format-Table -AutoSize
    
    $totalDuplicates = ($duplicates | Measure-Object -Property Count -Sum).Sum
    Write-Host ""
    Write-Host "Total duplicate records: $totalDuplicates" -ForegroundColor Yellow
    Write-Host "Unique record names with duplicates: $($duplicates.Count)" -ForegroundColor Yellow
}
else {
    Write-Host "No duplicate records found" -ForegroundColor Green
}
Write-Host ""

# 5. Empty/Invalid Records
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "5. EMPTY/INVALID RECORDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$emptyRecords = @()
foreach ($record in $allRecords) {
    $isEmpty = $false
    $reason = ""
    
    if ($record.RecordType -eq "A" -and -not $record.RecordData.IPv4Address) {
        $isEmpty = $true
        $reason = "A record without IPv4 address"
    }
    elseif ($record.RecordType -eq "AAAA" -and -not $record.RecordData.IPv6Address) {
        $isEmpty = $true
        $reason = "AAAA record without IPv6 address"
    }
    elseif ($record.RecordType -eq "CNAME" -and -not $record.RecordData.HostNameAlias) {
        $isEmpty = $true
        $reason = "CNAME record without target"
    }
    elseif ($record.RecordType -eq "MX" -and -not $record.RecordData.MailExchange) {
        $isEmpty = $true
        $reason = "MX record without mail exchange"
    }
    
    if ($isEmpty) {
        $emptyRecords += [PSCustomObject]@{
            HostName = $record.HostName
            RecordType = $record.RecordType
            Reason = $reason
        }
    }
}

if ($emptyRecords.Count -gt 0) {
    Write-Host "Found $($emptyRecords.Count) empty/invalid records:" -ForegroundColor Yellow
    $emptyRecords | Format-Table -AutoSize
}
else {
    Write-Host "No empty/invalid records found" -ForegroundColor Green
}
Write-Host ""

# 6. Old/Stale Records Analysis
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "6. OLD/STALE RECORDS ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check for records with very short TTL (might indicate problems)
$shortTTL = $allRecords | Where-Object { 
    $_.TimeToLive.TotalSeconds -lt 60 -and $_.RecordType -ne "SOA"
} | Select-Object -First 20

if ($shortTTL.Count -gt 0) {
    Write-Host "Records with very short TTL (<60s): $($shortTTL.Count)" -ForegroundColor Yellow
    $shortTTL | Select-Object HostName, RecordType, TimeToLive | Format-Table -AutoSize
}
else {
    Write-Host "No records with very short TTL found" -ForegroundColor Green
}

# Check for records with very long TTL (might be old static records)
$longTTL = $allRecords | Where-Object { 
    $_.TimeToLive.TotalHours -gt 24 -and $_.RecordType -ne "SOA" -and $_.RecordType -ne "NS"
} | Measure-Object

Write-Host ""
Write-Host "Records with long TTL (>24h): $($longTTL.Count)" -ForegroundColor White
Write-Host ""

# 7. HostName Analysis
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "7. HOSTNAME ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$uniqueHosts = ($allRecords | Select-Object -Unique HostName).Count
Write-Host "Unique hostnames: $uniqueHosts" -ForegroundColor White
Write-Host "Total records: $($allRecords.Count)" -ForegroundColor White
Write-Host "Average records per hostname: $([math]::Round($allRecords.Count / $uniqueHosts, 2))" -ForegroundColor White
Write-Host ""

# Find hostnames with many records
$hostsWithManyRecords = $allRecords | Group-Object HostName | 
    Where-Object { $_.Count -gt 5 } | 
    Sort-Object Count -Descending | 
    Select-Object -First 20

if ($hostsWithManyRecords.Count -gt 0) {
    Write-Host "Hostnames with many records (>5):" -ForegroundColor Yellow
    $hostsWithManyRecords | ForEach-Object {
        [PSCustomObject]@{
            HostName = $_.Name
            RecordCount = $_.Count
            RecordTypes = ($_.Group.RecordType | Sort-Object -Unique) -join ", "
        }
    } | Format-Table -AutoSize
}
Write-Host ""

# 8. IPv4/IPv6 Analysis
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "8. IP ADDRESS ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$ipv4Records = $allRecords | Where-Object { $_.RecordType -eq "A" }
$ipv6Records = $allRecords | Where-Object { $_.RecordType -eq "AAAA" }

Write-Host "IPv4 (A) Records: $($ipv4Records.Count)" -ForegroundColor White
Write-Host "IPv6 (AAAA) Records: $($ipv6Records.Count)" -ForegroundColor White
Write-Host "IPv6/IPv4 Ratio: $([math]::Round($ipv6Records.Count / $ipv4Records.Count, 2))" -ForegroundColor White
Write-Host ""

# Find hosts with only IPv4 or only IPv6
$hostsWithA = ($ipv4Records | Select-Object -Unique HostName).HostName
$hostsWithAAAA = ($ipv6Records | Select-Object -Unique HostName).HostName

$onlyIPv4 = $hostsWithA | Where-Object { $hostsWithAAAA -notcontains $_ }
$onlyIPv6 = $hostsWithAAAA | Where-Object { $hostsWithA -notcontains $_ }
$both = $hostsWithA | Where-Object { $hostsWithAAAA -contains $_ }

Write-Host "Hosts with only IPv4: $($onlyIPv4.Count)" -ForegroundColor White
Write-Host "Hosts with only IPv6: $($onlyIPv6.Count)" -ForegroundColor White
Write-Host "Hosts with both: $($both.Count)" -ForegroundColor White
Write-Host ""

# 9. Performance Impact Analysis
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "9. PERFORMANCE IMPACT ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Zone Size Impact:" -ForegroundColor Yellow
Write-Host "  Total Records: $($allRecords.Count)" -ForegroundColor White
Write-Host "  Unique Hostnames: $uniqueHosts" -ForegroundColor White
Write-Host "  Records per Hostname (avg): $([math]::Round($allRecords.Count / $uniqueHosts, 2))" -ForegroundColor White
Write-Host ""

$problemScore = 0
$issues = @()

if ($allRecords.Count -gt 1000) {
    $problemScore += 3
    $issues += "Zone has more than 1000 records (very large)"
}
elseif ($allRecords.Count -gt 500) {
    $problemScore += 2
    $issues += "Zone has more than 500 records (large)"
}

if ($duplicates.Count -gt 50) {
    $problemScore += 2
    $issues += "Many duplicate records found ($($duplicates.Count))"
}
elseif ($duplicates.Count -gt 10) {
    $problemScore += 1
    $issues += "Some duplicate records found ($($duplicates.Count))"
}

if ($emptyRecords.Count -gt 0) {
    $problemScore += 2
    $issues += "Empty/invalid records found ($($emptyRecords.Count))"
}

if ($onlyIPv6.Count -gt ($ipv4Records.Count * 0.3)) {
    $problemScore += 1
    $issues += "Many hosts have only IPv6 (may cause lookup delays)"
}

Write-Host "Performance Impact Score: $problemScore / 10" -ForegroundColor $(if ($problemScore -gt 5) { "Red" } elseif ($problemScore -gt 3) { "Yellow" } else { "Green" })
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "Identified Issues:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor White
    }
}
else {
    Write-Host "No major issues identified" -ForegroundColor Green
}
Write-Host ""

# 10. Recommendations
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "10. RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($allRecords.Count -gt 1000) {
    Write-Host "1. Zone is very large ($($allRecords.Count) records)" -ForegroundColor Yellow
    Write-Host "   - Consider splitting into subdomains" -ForegroundColor White
    Write-Host "   - Review if all records are still needed" -ForegroundColor White
    Write-Host ""
}

if ($duplicates.Count -gt 0) {
    Write-Host "2. Duplicate records found ($($duplicates.Count) groups)" -ForegroundColor Yellow
    Write-Host "   - Review and remove unnecessary duplicates" -ForegroundColor White
    Write-Host ""
}

if ($emptyRecords.Count -gt 0) {
    Write-Host "3. Empty/invalid records found ($($emptyRecords.Count))" -ForegroundColor Yellow
    Write-Host "   - Remove or fix invalid records" -ForegroundColor White
    Write-Host ""
}

Write-Host "4. General recommendations:" -ForegroundColor Yellow
Write-Host "   - Enable DNS Scavenging to remove stale records" -ForegroundColor White
Write-Host "   - Review TTL values (very short TTLs can cause performance issues)" -ForegroundColor White
Write-Host "   - Consider zone defragmentation if AD-integrated" -ForegroundColor White
Write-Host "   - Monitor DNS query performance after cleanup" -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
