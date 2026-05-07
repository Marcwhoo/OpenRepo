# Queries all configured print servers for shared printers and saves the list to a CSV cache.
# The cache is then used by Add-NetworkPrinters.ps1 to install printers on client machines.
# Run this as a scheduled baramundi job whenever the printer inventory changes.

$printServers = @(
    "<PRINT-SERVER-1>",
    "<PRINT-SERVER-2>",
    "<PRINT-SERVER-3>",
    "<PRINT-SERVER-4>",
    "<PRINT-SERVER-5>",
    "<PRINT-SERVER-6>",
    "<PRINT-SERVER-7>"
)
$outputFile = "\\<BARAMUNDI-SERVER>\dip$\Scripts\BDS\Printer cache\printer_cache.csv"

# Verify network path is reachable before querying servers
$parentPath = Split-Path $outputFile -Parent
if (-not (Test-Path -Path $parentPath)) {
    $tcpTest = Test-NetConnection -ComputerName "<BARAMUNDI-SERVER>" -Port 445 -WarningAction SilentlyContinue
    if (-not $tcpTest.TcpTestSucceeded) {
        Write-Host "Server <BARAMUNDI-SERVER> not reachable (port 445)."
    } else {
        Write-Host "Server reachable but path inaccessible or permission denied: $parentPath"
    }
    exit 1
}

$printerList = @()

foreach ($server in $printServers) {
    try {
        $printers = Get-WmiObject -Class Win32_Printer -ComputerName $server -ErrorAction SilentlyContinue |
                    Where-Object { $_.Shared -eq $true }
        foreach ($printer in $printers) {
            $printerList += [PSCustomObject]@{ PrinterPath = "\\$server\$($printer.ShareName)" }
        }
    } catch {
        Write-Host "Error querying ${server}: $_"
    }
}

if ($printerList) {
    $printerList | Export-Csv -Path $outputFile -NoTypeInformation -Delimiter "," -Force
    Write-Host "Printer cache saved: $outputFile ($($printerList.Count) printers)"
} else {
    Write-Host "No shared printers found on any server."
}
