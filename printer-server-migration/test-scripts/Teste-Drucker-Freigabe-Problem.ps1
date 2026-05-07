# ==================================================================
# Test-Script: Drucker mit Share-Freigabe Problem
# ==================================================================
# 
# Dieses Script testet die Erstellung und Freigabe eines Druckers,
# bei dem in der Log-Datei Probleme mit der Share-Freigabe auftraten.
#
# Test-Drucker: <LOCATION>-<MODEL>-<AREA>-SW
# Port: <IP-ADDRESS> <LOCATION>-<AREA>
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01"
)

$ErrorActionPreference = "Continue"

# Test-Daten (aus der Log-Datei - Drucker mit Share-Problem)
$originalPrinterName = "<LOCATION>-<MODEL>-<AREA>-SW"
$testIP = "<IP-ADDRESS>"
# WICHTIG: Port-Format wie bei funktionierenden Druckern: IP_xxx.xxx.xxx.xxx
$testPortName = "IP_$testIP"
# Teste verschiedene Windows Universal-Treiber
$testDriver = "Microsoft IPP Class Driver"  # Windows-eigener Universal-Treiber

Write-Host ""
Write-Host "=== TEST: DRUCKER MIT BEREINIGTEM NAMEN ===" -ForegroundColor Cyan
Write-Host "Zielserver: $ComputerName" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test-Daten:" -ForegroundColor Yellow
Write-Host "  Original Drucker-Name: $originalPrinterName" -ForegroundColor White
Write-Host "  Port-Name: $testPortName" -ForegroundColor White
Write-Host "  IP-Adresse: $testIP" -ForegroundColor White
Write-Host "  Treiber: $testDriver" -ForegroundColor White
Write-Host ""

# Funktion zum Bereinigen von Share-Namen (aus dem Import-Script)
function Remove-InvalidShareCharacters {
    param([string]$ShareName)
    
    if ([string]::IsNullOrWhiteSpace($ShareName)) {
        return $ShareName
    }
    
    # Windows Share-Namen: Nur alphanumerische Zeichen und Unterstriche erlaubt
    # Ersetze Leerzeichen durch Unterstriche
    $cleaned = $ShareName -replace '\s+', '_'
    
    # Ersetze Punkte durch Unterstriche (Punkte sind in Share-Namen nicht erlaubt)
    $cleaned = $cleaned -replace '\.', '_'
    
    # Ersetze Bindestriche durch Unterstriche (Bindestriche können Probleme verursachen)
    $cleaned = $cleaned -replace '-', '_'
    
    # Entferne ALLE ungültigen Zeichen: / \ , < > : " | ? * [ ] { } ( ) + = & % $ # @ ! ~ ` ^
    # Nur alphanumerisch und Unterstrich bleiben
    $cleaned = $cleaned -replace '[^a-zA-Z0-9_]', '_'
    
    # Entferne mehrfache Unterstriche
    $cleaned = $cleaned -replace '_+', '_'
    
    # Entferne führende/abschließende Unterstriche
    $cleaned = $cleaned.Trim('_')
    
    # Stelle sicher, dass der Name nicht leer ist
    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        $cleaned = "Printer_Share"
    }
    
    # Maximale Länge für Share-Namen: 80 Zeichen (Windows-Limit)
    if ($cleaned.Length -gt 80) {
        $cleaned = $cleaned.Substring(0, 80)
        $cleaned = $cleaned.Trim('_')
    }
    
    return $cleaned
}

# Prüfe Verbindung zum Server
Write-Host "=== SCHRITT 1: Verbindung prüfen ===" -ForegroundColor Cyan
try {
    $connection = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
    if (-not $connection) {
        Write-Host "  [FEHLER] Keine Verbindung zu $ComputerName möglich" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] Verbindung zu $ComputerName erfolgreich" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Verbindung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Prüfe ob Port existiert
Write-Host "=== SCHRITT 2: Port prüfen ===" -ForegroundColor Cyan
try {
    $existingPort = Get-PrinterPort -ComputerName $ComputerName -Name $testPortName -ErrorAction SilentlyContinue
    if ($existingPort) {
        Write-Host "  [OK] Port existiert: $testPortName" -ForegroundColor Green
        Write-Host "    IP-Adresse: $($existingPort.PrinterHostAddress)" -ForegroundColor Gray
    } else {
        Write-Host "  [WARNUNG] Port existiert nicht: $testPortName" -ForegroundColor Yellow
        Write-Host "    Versuche Port zu erstellen..." -ForegroundColor Yellow
        try {
            Add-PrinterPort -Name $testPortName -ComputerName $ComputerName -PrinterHostAddress $testIP -PortNumber 9100 -ErrorAction Stop
            Write-Host "  [OK] Port erstellt: $testPortName" -ForegroundColor Green
        } catch {
            Write-Host "  [FEHLER] Port konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
} catch {
    Write-Host "  [FEHLER] Fehler beim Prüfen des Ports: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Prüfe ob Treiber installiert ist
Write-Host "=== SCHRITT 3: Treiber prüfen ===" -ForegroundColor Cyan
try {
    $drivers = Get-PrinterDriver -ComputerName $ComputerName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $testDriver }
    if ($drivers) {
        Write-Host "  [OK] Treiber gefunden: $testDriver" -ForegroundColor Green
    } else {
        Write-Host "  [WARNUNG] Treiber nicht gefunden: $testDriver" -ForegroundColor Yellow
        Write-Host "    Bitte installieren Sie den Treiber manuell." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARNUNG] Konnte Treiber nicht prüfen: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Bereinige Drucker-Name
Write-Host "=== SCHRITT 4: Drucker-Name bereinigen ===" -ForegroundColor Cyan
$testPrinterName = Remove-InvalidShareCharacters -ShareName $originalPrinterName

# WICHTIG: Share-Namen sollten max. 12 Zeichen lang sein (Windows-Limit)
if ($testPrinterName.Length -gt 12) {
    $testShareName = $testPrinterName.Substring(0, 12)
    $testShareName = $testShareName.Trim('_')
    if ([string]::IsNullOrWhiteSpace($testShareName)) {
        $testShareName = "Printer_001"
    }
} else {
    $testShareName = $testPrinterName
}

Write-Host "  Original Drucker-Name: $originalPrinterName" -ForegroundColor White
Write-Host "  Bereinigter Drucker-Name: $testPrinterName" -ForegroundColor White
Write-Host "  Drucker-Name Länge: $($testPrinterName.Length) Zeichen" -ForegroundColor Gray
Write-Host "  Share-Name: $testShareName" -ForegroundColor White
Write-Host "  Share-Name Länge: $($testShareName.Length) Zeichen" -ForegroundColor Gray

# Prüfe auf ungültige Zeichen im Drucker-Name
if ($testPrinterName -match '[,/\\]') {
    Write-Host "  [FEHLER] Drucker-Name enthält noch ungültige Zeichen!" -ForegroundColor Red
    Write-Host "    Ungültige Zeichen gefunden: $($testPrinterName -match '[,/\\]')" -ForegroundColor Red
} else {
    Write-Host "  [OK] Drucker-Name enthält keine ungültigen Zeichen" -ForegroundColor Green
}
Write-Host ""

# Lösche Drucker falls vorhanden (sowohl Original- als auch bereinigter Name)
Write-Host "=== SCHRITT 5: Alten Drucker löschen (falls vorhanden) ===" -ForegroundColor Cyan
$printersToDelete = @($originalPrinterName, $testPrinterName)
foreach ($printerToDelete in $printersToDelete) {
    try {
        $existingPrinter = Get-Printer -ComputerName $ComputerName -Name $printerToDelete -ErrorAction SilentlyContinue
        if ($existingPrinter) {
            Write-Host "  [INFO] Drucker '$printerToDelete' existiert, lösche..." -ForegroundColor Yellow
            # Versuche zuerst, den Drucker zu deaktivieren
            try {
                Set-Printer -ComputerName $ComputerName -Name $printerToDelete -Shared $false -ErrorAction SilentlyContinue
            } catch {}
            Start-Sleep -Seconds 1
            # Lösche alle Druckaufträge
            try {
                $jobs = Get-PrintJob -ComputerName $ComputerName -PrinterName $printerToDelete -ErrorAction SilentlyContinue
                if ($jobs) {
                    $jobs | Remove-PrintJob -ErrorAction SilentlyContinue
                }
            } catch {}
            Start-Sleep -Seconds 1
            # Lösche den Drucker - mehrfach versuchen
            $deleted = $false
            for ($i = 1; $i -le 3; $i++) {
                try {
                    Remove-Printer -ComputerName $ComputerName -Name $printerToDelete -ErrorAction Stop
                    Write-Host "  [OK] Drucker '$printerToDelete' gelöscht (Versuch $i)" -ForegroundColor Green
                    $deleted = $true
                    break
                } catch {
                    if ($i -lt 3) {
                        Write-Host "  [INFO] Versuch $i fehlgeschlagen, warte 2 Sekunden..." -ForegroundColor Gray
                        Start-Sleep -Seconds 2
                    } else {
                        Write-Host "  [WARNUNG] Konnte Drucker '$printerToDelete' nicht löschen: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "    Bitte löschen Sie den Drucker manuell auf $ComputerName" -ForegroundColor Yellow
                    }
                }
            }
            if ($deleted) {
                Start-Sleep -Seconds 2
            }
        }
    } catch {
        Write-Host "  [WARNUNG] Fehler beim Prüfen/Löschen von '$printerToDelete': $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Host ""

# Erstelle Drucker DIREKT mit Freigabe
Write-Host "=== SCHRITT 6: Drucker erstellen (DIREKT mit Freigabe) ===" -ForegroundColor Cyan
Write-Host "  Erstelle Drucker direkt mit -Shared $true und -ShareName..." -ForegroundColor Gray
Write-Host ""

try {
    # Add-Printer unterstützt -Shared und -ShareName Parameter!
    $printerParams = @{
        Name = $testPrinterName
        ComputerName = $ComputerName
        DriverName = $testDriver
        PortName = $testPortName
        Shared = $true
        ShareName = $testShareName
        ErrorAction = "Stop"
    }
    
    Add-Printer @printerParams
    Write-Host "  [OK] Drucker DIREKT mit Freigabe erstellt: $testPrinterName" -ForegroundColor Green
    Write-Host "    Share-Name: $testShareName" -ForegroundColor Gray
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  [FEHLER] Konnte Drucker nicht mit Freigabe erstellen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Fehler-Details:" -ForegroundColor Red
    Write-Host "      $($_.Exception.GetType().FullName)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "      Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  [FEHLER] Drucker-Erstellung fehlgeschlagen!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Verifikation
Write-Host "=== SCHRITT 7: Verifikation ===" -ForegroundColor Cyan
try {
    $importedPrinter = Get-Printer -ComputerName $ComputerName -Name $testPrinterName -ErrorAction SilentlyContinue
    if ($importedPrinter) {
        Write-Host "  [OK] Drucker gefunden: $($importedPrinter.Name)" -ForegroundColor Green
        Write-Host "    Shared: $($importedPrinter.Shared)" -ForegroundColor Gray
        Write-Host "    ShareName: $($importedPrinter.ShareName)" -ForegroundColor Gray
        Write-Host "    PortName: $($importedPrinter.PortName)" -ForegroundColor Gray
        Write-Host "    DriverName: $($importedPrinter.DriverName)" -ForegroundColor Gray
        
        if ($importedPrinter.Shared -eq $true) {
            Write-Host "  [OK] Drucker ist geteilt!" -ForegroundColor Green
            if ($importedPrinter.ShareName) {
                Write-Host "  [OK] Share-Name gesetzt: $($importedPrinter.ShareName)" -ForegroundColor Green
            } else {
                Write-Host "  [WARNUNG] Share-Name ist leer (Windows hat Standard-Name verwendet)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [FEHLER] Drucker ist NICHT geteilt!" -ForegroundColor Red
        }
    } else {
        Write-Host "  [FEHLER] Drucker wurde nicht gefunden!" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FEHLER] Fehler bei der Verifikation: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== TEST ABGESCHLOSSEN ===" -ForegroundColor Cyan
Write-Host ""

