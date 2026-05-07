param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01"
)

Write-Host "=== Entferne 'Jeder' Berechtigung von allen Druckern ===" -ForegroundColor Cyan
Write-Host "Server: $ComputerName" -ForegroundColor Yellow
Write-Host ""

# Führe Script direkt auf dem Server aus für bessere Performance
$scriptBlock = {
    $allPrintersWmi = Get-WmiObject -Class Win32_Printer -ErrorAction Stop
    $successCount = 0
    $errorCount = 0
    $skippedCount = 0
    $total = $allPrintersWmi.Count
    $current = 0
    $details = @()
    
    foreach ($printerWmi in $allPrintersWmi) {
        $current++
        $printerName = $printerWmi.Name
        
        try {
            # Hole Security Descriptor
            $sdResult = $printerWmi.GetSecurityDescriptor()
            if ($sdResult.ReturnValue -ne 0) {
                Write-Host "[$current/$total] $printerName - Konnte Berechtigungen nicht abrufen" -ForegroundColor Yellow
                $skippedCount++
                continue
            }
            
            $descriptor = $sdResult.Descriptor
            $modified = $false
            $newDacl = New-Object System.Collections.ArrayList
            
            # Durchlaufe alle ACEs (Access Control Entries)
            foreach ($ace in $descriptor.DACL) {
                $sid = $ace.Trustee.SIDString
                
                # S-1-1-0 ist der SID für "Everyone" (Jeder)
                if ($sid -like "S-1-1-0*") {
                    $modified = $true
                } else {
                    [void]$newDacl.Add($ace)
                }
            }
            
            if ($modified) {
                # Setze neue DACL ohne "Everyone"
                $descriptor.DACL = $newDacl.ToArray()
                $setResult = $printerWmi.SetSecurityDescriptor($descriptor)
                
                if ($setResult.ReturnValue -eq 0) {
                    Write-Host "[$current/$total] $printerName - 'Jeder' entfernt" -ForegroundColor Green
                    $successCount++
                } else {
                    Write-Host "[$current/$total] $printerName - Fehler beim Setzen (Code: $($setResult.ReturnValue))" -ForegroundColor Red
                    $errorCount++
                }
            } else {
                Write-Host "[$current/$total] $printerName - Keine 'Jeder' Berechtigung" -ForegroundColor Gray
                $skippedCount++
            }
            
        } catch {
            Write-Host "[$current/$total] $printerName - Fehler: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
    }
    
    return @{
        Success = $successCount
        Error = $errorCount
        Skipped = $skippedCount
        Total = $total
    }
}

Write-Host "Führe Script auf Server aus..." -ForegroundColor Yellow
$result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ErrorAction Stop

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Erfolgreich entfernt: $($result.Success)" -ForegroundColor Green
Write-Host "Übersprungen (keine 'Jeder' Berechtigung): $($result.Skipped)" -ForegroundColor Gray
Write-Host "Fehler: $($result.Error)" -ForegroundColor $(if ($result.Error -gt 0) { "Red" } else { "Gray" })
Write-Host "Gesamt: $($result.Total)" -ForegroundColor White
