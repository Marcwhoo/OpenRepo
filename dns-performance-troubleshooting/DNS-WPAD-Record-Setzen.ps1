# DNS WPAD Record Setzen
# Erstellt oder aktualisiert den WPAD-Record in der DNS-Zone

param(
    [Parameter(Mandatory=$false)]
    [string]$DcName = "<DC-SERVER>",
    [Parameter(Mandatory=$false)]
    [string]$ZoneName = "<DOMAIN-FQDN>",
    [Parameter(Mandatory=$false)]
    [string]$WpadIpAddress = "",
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS WPAD Record Setzen" -ForegroundColor Cyan
Write-Host "DC: $DcName" -ForegroundColor Yellow
Write-Host "Zone: $ZoneName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Prüfe ob WPAD-Record bereits existiert
Write-Host "1. Prüfe vorhandene WPAD-Records..." -ForegroundColor Cyan
$existingRecords = Invoke-Command -ComputerName $DcName -ScriptBlock {
    param($zone)
    Get-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -ErrorAction SilentlyContinue
} -ArgumentList $ZoneName

if ($existingRecords) {
    Write-Host "   Gefunden: $($existingRecords.Count) WPAD-Record(s)" -ForegroundColor Yellow
    foreach ($record in $existingRecords) {
        Write-Host "   - $($record.HostName) ($($record.RecordType)): $($record.RecordData)" -ForegroundColor White
    }
    
    if (-not $Force) {
        Write-Host ""
        Write-Host "WPAD-Record existiert bereits!" -ForegroundColor Yellow
        Write-Host "Verwende -Force um den Record zu ueberschreiben." -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host ""
        Write-Host "   Loesche vorhandene WPAD-Records..." -NoNewline
        Invoke-Command -ComputerName $DcName -ScriptBlock {
            param($zone)
            $records = Get-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -ErrorAction SilentlyContinue
            foreach ($record in $records) {
                Remove-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -RecordType $record.RecordType -RRData $record.RecordData -Force -ErrorAction SilentlyContinue
            }
        } -ArgumentList $ZoneName
        Write-Host " OK" -ForegroundColor Green
    }
} else {
    Write-Host "   Kein WPAD-Record gefunden" -ForegroundColor Green
}
Write-Host ""

# 2. Bestimme IP-Adresse für WPAD
if ([string]::IsNullOrWhiteSpace($WpadIpAddress)) {
    Write-Host "2. Bestimme IP-Adresse für WPAD..." -ForegroundColor Cyan
    
    # Versuche die IP des DCs zu verwenden
    try {
        $dcIp = (Resolve-DnsName -Name $DcName -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" }).IPAddress | Select-Object -First 1
        Write-Host "   DC IP: $dcIp" -ForegroundColor White
        
        $WpadIpAddress = $dcIp
        Write-Host "   Verwende DC IP als WPAD-Adresse: $WpadIpAddress" -ForegroundColor Yellow
        Write-Host "   (Hinweis: Falls ein Proxy-Server verwendet wird, bitte IP manuell angeben)" -ForegroundColor Gray
    }
    catch {
        Write-Host "   ERROR: Konnte DC IP nicht aufloesen" -ForegroundColor Red
        Write-Host "   Bitte IP-Adresse manuell angeben mit -WpadIpAddress" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "2. Verwende angegebene IP-Adresse: $WpadIpAddress" -ForegroundColor Cyan
}

# Validiere IP-Adresse
if (-not ($WpadIpAddress -match '^(\d{1,3}\.){3}\d{1,3}$')) {
    Write-Host "   ERROR: Ungueltige IP-Adresse: $WpadIpAddress" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 3. Erstelle WPAD A-Record
Write-Host "3. Erstelle WPAD A-Record..." -ForegroundColor Cyan
Write-Host "   Name: wpad" -ForegroundColor White
Write-Host "   Zone: $ZoneName" -ForegroundColor White
Write-Host "   IP: $WpadIpAddress" -ForegroundColor White

try {
    $result = Invoke-Command -ComputerName $DcName -ScriptBlock {
        param($zone, $ip)
        Add-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -A -IPv4Address $ip -ErrorAction Stop
        return Get-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -ErrorAction Stop
    } -ArgumentList $ZoneName, $WpadIpAddress
    
    Write-Host "   OK - WPAD-Record erstellt" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Details:" -ForegroundColor Yellow
    Write-Host "   - Name: $($result.HostName)" -ForegroundColor White
    Write-Host "   - Type: $($result.RecordType)" -ForegroundColor White
    Write-Host "   - IP: $($result.RecordData.IPv4Address)" -ForegroundColor White
    Write-Host "   - TTL: $($result.TimeToLive) seconds" -ForegroundColor White
}
catch {
    Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 4. Teste WPAD-Aufloesung
Write-Host "4. Teste WPAD-Aufloesung..." -ForegroundColor Cyan
$testCount = 5
$times = @()
for ($i = 1; $i -le $testCount; $i++) {
    $start = Get-Date
    try {
        $result = Resolve-DnsName -Name "wpad.$ZoneName" -Server $DcName -ErrorAction Stop
        $end = Get-Date
        $duration = ($end - $start).TotalMilliseconds
        $times += $duration
    }
    catch {
        Write-Host "   ERROR bei Test ${i}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($times.Count -gt 0) {
    $avg = ($times | Measure-Object -Average).Average
    $min = ($times | Measure-Object -Minimum).Minimum
    $max = ($times | Measure-Object -Maximum).Maximum
    
    Write-Host "   Aufloesung erfolgreich!" -ForegroundColor Green
    Write-Host "   Avg: $([math]::Round($avg, 2))ms, Min: $([math]::Round($min, 2))ms, Max: $([math]::Round($max, 2))ms" -ForegroundColor White
    
    $resolvedIp = (Resolve-DnsName -Name "wpad.$ZoneName" -Server $DcName -Type A).IPAddress
    Write-Host "   Aufgeloeste IP: $resolvedIp" -ForegroundColor White
} else {
    Write-Host "   WARNING: WPAD-Aufloesung fehlgeschlagen" -ForegroundColor Yellow
    Write-Host "   (DNS-Replikation kann einige Minuten dauern)" -ForegroundColor Gray
}
Write-Host ""

# 5. Prüfe Replikation
Write-Host "5. Prüfe Replikation auf DC02..." -ForegroundColor Cyan
try {
    $dc02Records = Invoke-Command -ComputerName "<DC-SERVER>" -ScriptBlock {
        param($zone)
        Get-DnsServerResourceRecord -ZoneName $zone -Name "wpad" -ErrorAction SilentlyContinue
    } -ArgumentList $ZoneName
    
    if ($dc02Records) {
        Write-Host "   OK - WPAD-Record auf DC02 gefunden" -ForegroundColor Green
        Write-Host "   - $($dc02Records[0].HostName) ($($dc02Records[0].RecordType)): $($dc02Records[0].RecordData.IPv4Address)" -ForegroundColor White
    } else {
        Write-Host "   WARNING - WPAD-Record noch nicht auf DC02" -ForegroundColor Yellow
        Write-Host "   (Replikation kann einige Minuten dauern)" -ForegroundColor Gray
    }
}
catch {
    Write-Host "   WARNING - Konnte DC02 nicht erreichen: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WPAD-Record erfolgreich erstellt!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Hinweise:" -ForegroundColor Yellow
Write-Host "- WPAD-Record zeigt auf: $WpadIpAddress" -ForegroundColor White
Write-Host "- Falls ein Proxy-Server verwendet wird, sollte dieser auf Port 80/8080 erreichbar sein" -ForegroundColor Gray
Write-Host "- Clients muessen moeglicherweise neu gestartet werden, um WPAD zu verwenden" -ForegroundColor Gray
Write-Host "- Falls kein Proxy verwendet wird, kann WPAD in den Browser-Einstellungen deaktiviert werden" -ForegroundColor Gray
