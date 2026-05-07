# Client-Script zum Entfernen aller Drucker von alten Druckerservern
# Dieses Script sollte per GPO als Startup/Logon Script verteilt werden
# Es entfernt alle Drucker, die von den konfigurierten alten Druckerservern stammen

param(
    [Parameter(Mandatory=$false)]
    [string[]]$OldPrintServers = @("<PRINT-SERVER-1>", "<PRINT-SERVER-2>", "<PRINT-SERVER-3>"),
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Hole alle lokalen Drucker
try {
    $allPrinters = Get-Printer -ErrorAction Stop | Where-Object { 
        $_.Name -notlike "Microsoft*" -and 
        $_.Name -notlike "Fax*" -and
        $_.Name -notlike "OneNote*" -and
        $_.Name -notlike "Send To*"
    }
} catch {
    exit 1
}

foreach ($printer in $allPrinters) {
    $printerName = $printer.Name
    $printerPort = $printer.PortName
    
    # Prüfe, ob der Drucker von einem alten Server stammt
    $isFromOldServer = $false
    
    foreach ($oldServer in $OldPrintServers) {
        # Normalisiere Servernamen (ohne Backslashes)
        $serverName = $oldServer.TrimStart('\')
        
        # Prüfe Port-Name (häufigster Fall: \\Server\DruckerName)
        # Exakter Match: \\Server\ oder \\Server\DruckerName (nicht \\Server-01\)
        if ($printerPort -and ($printerPort -eq "\\$serverName\" -or $printerPort -like "\\$serverName\*")) {
            $isFromOldServer = $true
            break
        }
        
        # Prüfe SharePath falls verfügbar (PowerShell 5.1+)
        if ($printer.SharePath -and ($printer.SharePath -eq "\\$serverName\" -or $printer.SharePath -like "\\$serverName\*")) {
            $isFromOldServer = $true
            break
        }
        
        # Prüfe ComputerName falls verfügbar (exakter Match)
        if ($printer.ComputerName -and $printer.ComputerName -eq $serverName) {
            $isFromOldServer = $true
            break
        }
    }
    
    if ($isFromOldServer -and -not $WhatIf) {
        try {
            Remove-Printer -Name $printerName -ErrorAction SilentlyContinue
        } catch {
            # Fehler beim Entfernen, überspringen
        }
    }
}

exit 0
