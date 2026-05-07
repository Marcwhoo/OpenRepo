# DNS Wireshark Trace Script
# Captures DNS traffic using tshark during RDS login

param(
    [int]$DurationMinutes = 5,
    [string]$OutputPath = ".\DNS-Trace",
    [string]$Filter = "udp.port == 53 or tcp.port == 53",
    [switch]$AutoAnalyze = $true
)

$tsharkPath = "C:\Program Files\Wireshark\tshark.exe"

if (-not (Test-Path $tsharkPath)) {
    Write-Host "ERROR: tshark.exe not found at $tsharkPath" -ForegroundColor Red
    Write-Host "Please ensure Wireshark is installed." -ForegroundColor Yellow
    exit 1
}

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator. Packet capture may fail." -ForegroundColor Yellow
    Write-Host "Please run PowerShell as Administrator for full functionality." -ForegroundColor Yellow
}

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outputFile = Join-Path $OutputPath "DNS-Trace-$timestamp.pcapng"
$durationSeconds = $DurationMinutes * 60

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DNS Wireshark Trace" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Yellow
Write-Host "Filter: $Filter" -ForegroundColor Yellow
Write-Host "Output: $outputFile" -ForegroundColor Yellow
Write-Host ""

# Get network interfaces and find active one
Write-Host "Detecting active network interface..." -NoNewline
$interfaces = & $tsharkPath -D 2>&1
$activeInterface = $interfaces | Where-Object { $_ -match 'Ethernet' -and $_ -notmatch 'Loopback' } | Select-Object -First 1

if ($activeInterface) {
    $interfaceNum = ($activeInterface -split '\.')[0].Trim()
    Write-Host " OK (Interface $interfaceNum)" -ForegroundColor Green
    Write-Host "  $activeInterface" -ForegroundColor Gray
}
else {
    $interfaceNum = "0"
    Write-Host " Using default (Interface 0)" -ForegroundColor Yellow
}

Write-Host "`nStarting capture..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop early" -ForegroundColor Yellow
Write-Host ""

# Start tshark capture
$tsharkArgs = @(
    "-i", $interfaceNum,
    "-f", $Filter,
    "-w", $outputFile,
    "-a", "duration:$durationSeconds"
)

try {
    Write-Host "Capturing DNS traffic..." -ForegroundColor Green
    & $tsharkPath $tsharkArgs
    
    if (Test-Path $outputFile) {
        $fileSize = (Get-Item $outputFile).Length / 1MB
        Write-Host "`n[OK] Capture completed!" -ForegroundColor Green
        Write-Host "File: $outputFile" -ForegroundColor Cyan
        Write-Host "Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
        
        # Analyze capture
        Write-Host "`nAnalyzing capture..." -ForegroundColor Cyan
        try {
            $dnsCount = & $tsharkPath -r $outputFile -Y "dns" -T fields -e frame.number 2>&1 | Measure-Object -Line
            Write-Host "DNS packets captured: $($dnsCount.Lines)" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not analyze capture (file may be empty)" -ForegroundColor Yellow
        }
        
        # Auto-analyze if requested
        if ($AutoAnalyze -and $dnsCount.Lines -gt 0) {
            $analysisScript = Join-Path $PSScriptRoot "DNS-Wireshark-Analyse.ps1"
            if (Test-Path $analysisScript) {
                Write-Host "`nRunning automatic analysis..." -ForegroundColor Cyan
                $analysisCsv = $outputFile -replace "\.pcapng$", "_Analysis.csv"
                try {
                    & $analysisScript -PcapngFile $outputFile -OutputCsv $analysisCsv
                }
                catch {
                    Write-Host "Analysis failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "`nAnalysis script not found: $analysisScript" -ForegroundColor Yellow
            }
        }
        
        Write-Host "`nTo analyze in Wireshark GUI:" -ForegroundColor Cyan
        Write-Host "  wireshark.exe `"$outputFile`"" -ForegroundColor White
        Write-Host "`nOr use analysis script:" -ForegroundColor Cyan
        Write-Host "  .\DNS-Wireshark-Analyse.ps1 -PcapngFile `"$outputFile`"" -ForegroundColor White
    }
    else {
        Write-Host "[ERROR] Capture file was not created!" -ForegroundColor Red
    }
}
catch {
    Write-Host "[ERROR] Capture failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
