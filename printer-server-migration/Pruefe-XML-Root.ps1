$gpo = Get-GPO -Name "Drucker - <PRINT-SERVER-1>-01 - Alle Drucker" -ErrorAction SilentlyContinue
if ($gpo) {
    $domainName = (Get-ADDomain).DNSRoot
    $xmlPath = "\\$domainName\SYSVOL\$domainName\Policies\{$($gpo.Id)}\User\Preferences\Printers\Printers.xml"
    if (Test-Path $xmlPath) {
        [xml]$xml = Get-Content $xmlPath -Encoding UTF8
        
        Write-Host "=== XML-Struktur-Prüfung ===" -ForegroundColor Cyan
        Write-Host ""
        
        # Prüfe Root-Element
        if ($xml.DocumentElement) {
            Write-Host "[OK] Root-Element vorhanden: $($xml.DocumentElement.Name)" -ForegroundColor Green
            Write-Host "  CLSID: $($xml.DocumentElement.GetAttribute('clsid'))" -ForegroundColor Gray
            
            # Zähle SharedPrinter-Elemente
            $printers = $xml.SelectNodes("//SharedPrinter")
            Write-Host ""
            Write-Host "Gefundene SharedPrinter-Elemente: $($printers.Count)" -ForegroundColor Yellow
            
            # Prüfe ob sie direkt unter Root sind
            $rootPrinters = $xml.DocumentElement.SelectNodes("SharedPrinter")
            Write-Host "SharedPrinter direkt unter Root: $($rootPrinters.Count)" -ForegroundColor Yellow
            
            if ($printers.Count -ne $rootPrinters.Count) {
                Write-Host "[WARNUNG] Nicht alle SharedPrinter sind direkt unter Root!" -ForegroundColor Red
            }
            
            # Prüfe erste 3 Drucker
            Write-Host ""
            Write-Host "Erste 3 Drucker:" -ForegroundColor Cyan
            $printers | Select-Object -First 3 | ForEach-Object {
                $name = $_.GetAttribute("name")
                $parent = $_.ParentNode.Name
                Write-Host "  - $name (Parent: $parent)" -ForegroundColor White
            }
        } else {
            Write-Host "[FEHLER] Kein Root-Element gefunden!" -ForegroundColor Red
        }
        
        # Prüfe XML-Formatierung
        Write-Host ""
        Write-Host "=== XML-Formatierung ===" -ForegroundColor Cyan
        $content = Get-Content $xmlPath -Raw
        if ($content -match "^\s*<\?xml") {
            Write-Host "[OK] XML-Deklaration vorhanden" -ForegroundColor Green
        } else {
            Write-Host "[WARNUNG] XML-Deklaration fehlt oder falsch formatiert" -ForegroundColor Yellow
        }
        
        # Prüfe auf BOM
        $bytes = [System.IO.File]::ReadAllBytes($xmlPath)
        if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Write-Host "[WARNUNG] UTF-8 BOM gefunden (sollte nicht vorhanden sein)" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Kein UTF-8 BOM gefunden" -ForegroundColor Green
        }
    } else {
        Write-Host "[FEHLER] XML-Datei nicht gefunden: $xmlPath" -ForegroundColor Red
    }
} else {
    Write-Host "[FEHLER] GPO nicht gefunden" -ForegroundColor Red
}
