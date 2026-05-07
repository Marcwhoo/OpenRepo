$gpo = Get-GPO -Name "Drucker - <PRINT-SERVER-1>-01 - Alle Drucker" -ErrorAction SilentlyContinue
if ($gpo) {
    $domainName = (Get-ADDomain).DNSRoot
    $xmlPath = "\\$domainName\SYSVOL\$domainName\Policies\{$($gpo.Id)}\User\Preferences\Printers\Printers.xml"
    if (Test-Path $xmlPath) {
        [xml]$xml = Get-Content $xmlPath -Encoding UTF8
        $firstPrinter = $xml.SelectSingleNode("//SharedPrinter")
        if ($firstPrinter) {
            Write-Host "=== Erster Drucker-Eintrag ===" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "SharedPrinter Attributes:" -ForegroundColor Yellow
            foreach ($attr in $firstPrinter.Attributes) {
                Write-Host "  $($attr.Name) = $($attr.Value)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Properties:" -ForegroundColor Yellow
            $props = $firstPrinter.SelectSingleNode("Properties")
            if ($props) {
                foreach ($attr in $props.Attributes) {
                    Write-Host "  $($attr.Name) = $($attr.Value)" -ForegroundColor White
                }
            } else {
                Write-Host "  [FEHLER] Kein Properties-Element gefunden!" -ForegroundColor Red
            }
            Write-Host ""
            Write-Host "Filters:" -ForegroundColor Yellow
            $filters = $firstPrinter.SelectSingleNode("Filters")
            if ($filters) {
                $filterGroup = $filters.SelectSingleNode("FilterGroup")
                if ($filterGroup) {
                    foreach ($attr in $filterGroup.Attributes) {
                        Write-Host "  $($attr.Name) = $($attr.Value)" -ForegroundColor White
                    }
                } else {
                    Write-Host "  [FEHLER] Kein FilterGroup-Element gefunden!" -ForegroundColor Red
                }
            } else {
                Write-Host "  [FEHLER] Kein Filters-Element gefunden!" -ForegroundColor Red
            }
            
            # Prüfe auf kritische Attribute
            Write-Host ""
            Write-Host "=== Prüfung kritischer Attribute ===" -ForegroundColor Cyan
            $issues = @()
            
            if (-not $firstPrinter.GetAttribute("removePolicy")) {
                $issues += "removePolicy fehlt"
            } elseif ($firstPrinter.GetAttribute("removePolicy") -ne "1") {
                $issues += "removePolicy ist nicht '1' (aktuell: $($firstPrinter.GetAttribute('removePolicy')))"
            }
            
            $props = $firstPrinter.SelectSingleNode("Properties")
            if ($props) {
                if (-not $props.GetAttribute("action")) {
                    $issues += "Properties.action fehlt"
                } elseif ($props.GetAttribute("action") -ne "C") {
                    $issues += "Properties.action ist nicht 'C' (aktuell: $($props.GetAttribute('action')))"
                }
                if (-not $props.GetAttribute("deleteMaps")) {
                    $issues += "Properties.deleteMaps fehlt"
                } elseif ($props.GetAttribute("deleteMaps") -ne "1") {
                    $issues += "Properties.deleteMaps ist nicht '1' (aktuell: $($props.GetAttribute('deleteMaps')))"
                }
            } else {
                $issues += "Properties-Element fehlt komplett"
            }
            
            $filterGroup = $firstPrinter.SelectSingleNode("Filters/FilterGroup")
            if ($filterGroup) {
                if (-not $filterGroup.GetAttribute("sid")) {
                    $issues += "FilterGroup.sid fehlt"
                }
                if (-not $filterGroup.GetAttribute("name")) {
                    $issues += "FilterGroup.name fehlt"
                }
            } else {
                $issues += "FilterGroup fehlt komplett"
            }
            
            if ($issues.Count -gt 0) {
                Write-Host "[PROBLEME GEFUNDEN]:" -ForegroundColor Red
                foreach ($issue in $issues) {
                    Write-Host "  - $issue" -ForegroundColor Red
                }
            } else {
                Write-Host "[OK] Alle kritischen Attribute vorhanden" -ForegroundColor Green
            }
        } else {
            Write-Host "[FEHLER] Kein SharedPrinter-Element gefunden!" -ForegroundColor Red
        }
    } else {
        Write-Host "[FEHLER] XML-Datei nicht gefunden: $xmlPath" -ForegroundColor Red
    }
} else {
    Write-Host "[FEHLER] GPO nicht gefunden" -ForegroundColor Red
}
