# Adds all printers from the cached printer list (CSV) to the current user session.
# Removes connections to old/decommissioned print servers.
# Intended to run as baramundi job in user context.

$cacheFile = "\\<BARAMUNDI-SERVER>\dip$\Scripts\BDS\Printer cache\printer_cache.csv"

function Add-NetworkPrinter {
    param ([string]$printerPath)
    try {
        if (-not (Get-Printer -Name $printerPath -ErrorAction SilentlyContinue)) {
            Add-Printer -ConnectionName $printerPath
            Write-Host "Added: $printerPath"
        }
    } catch {
        # Permission denied - user has no access to this printer, expected behavior
    }
}

if (Test-Path $cacheFile) {
    $printers = Import-Csv -Path $cacheFile -Delimiter ","
    foreach ($printer in $printers) {
        if ($printer.PrinterPath) {
            Add-NetworkPrinter -printerPath $printer.PrinterPath
        }
    }
} else {
    Write-Host "Cache file not found: $cacheFile"
}

# Remove connections to old print servers that are no longer valid
$validServers = @("<PRINT-SERVER-1>", "<PRINT-SERVER-2>", "<PRINT-SERVER-3>", "<PRINT-SERVER-4>", "<PRINT-SERVER-5>", "<PRINT-SERVER-6>")
$validServersLower = $validServers | ForEach-Object { $_.ToLower() }
$currentPrinters = Get-Printer | Where-Object { $_.Type -eq "Connection" } | Select-Object -ExpandProperty Name

foreach ($printer in $currentPrinters) {
    $server = ($printer -split "\\")[2].ToLower()
    if ($validServersLower -notcontains $server) {
        Remove-Printer -Name $printer -ErrorAction SilentlyContinue
        Write-Host "Removed stale printer: $printer"
    }
}

$printers = Get-Printer
if ($printers.Count -gt 0) {
    Set-Printer -Name $printers[0].Name -Default -ErrorAction SilentlyContinue
}
