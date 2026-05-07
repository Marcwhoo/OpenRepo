# ==================================================================
# Phase 2.6: Importiert nur Treiber aus Printbrm-Export-Dateien
# Löscht nur die importierten Drucker/Ports, nicht die bereits vorhandenen
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetServer = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipConfirmation = $false
)

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

# Prüfe ob ScriptDir korrekt ist, falls nicht, versuche absoluten Pfad
if (-not (Test-Path $ScriptDir)) {
    $ScriptDir = $PSScriptRoot
}

$ExportDir = Join-Path $ScriptDir "Export"
$LogDir = Join-Path $ScriptDir "Logs"
$LogFile = Join-Path $LogDir "2.6-Importiere-nur-Treiber_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Debug-Ausgabe
Write-Host "Script-Verzeichnis: $ScriptDir" -ForegroundColor Gray
Write-Host "Export-Verzeichnis: $ExportDir" -ForegroundColor Gray

# Erstelle Log-Verzeichnis
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Logging-Funktion
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

Write-Host ""
Write-Host "=== IMPORT NUR TREIBER ===" -ForegroundColor Cyan
Write-Host "Zielserver: $TargetServer" -ForegroundColor Yellow
Write-Host "Export-Ordner: $ExportDir" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

# Prüfe ob Export-Ordner existiert
Write-Host "Prüfe Export-Ordner: $ExportDir" -ForegroundColor Cyan
if (-not (Test-Path $ExportDir)) {
    Write-Log "FEHLER: Export-Ordner nicht gefunden: $ExportDir" "ERROR"
    Write-Host "  [FEHLER] Export-Ordner nicht gefunden!" -ForegroundColor Red
    Write-Host "  Gesuchter Pfad: $ExportDir" -ForegroundColor Yellow
    Write-Host "  Aktuelles Verzeichnis: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "  Script-Verzeichnis: $ScriptDir" -ForegroundColor Yellow
    
    # Versuche alternativen Pfad
    $altExportDir = "(Join-Path $PSScriptRoot "Export")"
    Write-Host "  Versuche alternativen Pfad: $altExportDir" -ForegroundColor Yellow
    if (Test-Path $altExportDir) {
        Write-Host "  [OK] Alternativer Pfad gefunden!" -ForegroundColor Green
        $ExportDir = $altExportDir
    } else {
        Write-Host "Drücke eine Taste zum Beenden..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
} else {
    Write-Host "  [OK] Export-Ordner gefunden" -ForegroundColor Green
}

# Prüfe Verbindung zum Zielserver (wenn nicht localhost)
if ($TargetServer -ne "localhost" -and $TargetServer -ne $env:COMPUTERNAME) {
    Write-Host "Prüfe Verbindung zu $TargetServer..." -ForegroundColor Cyan
    if (-not (Test-Connection -ComputerName $TargetServer -Count 1 -Quiet)) {
        Write-Log "FEHLER: Zielserver $TargetServer ist nicht erreichbar!" "ERROR"
        Write-Host "  [FEHLER] Zielserver ist nicht erreichbar!" -ForegroundColor Red
        Write-Host "Drücke eine Taste zum Beenden..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    Write-Host "  [OK] Server ist erreichbar" -ForegroundColor Green
} else {
    Write-Host "Lokaler Server erkannt: $env:COMPUTERNAME" -ForegroundColor Green
    $TargetServer = "localhost"
}

# Hole Liste der bereits vorhandenen Drucker und Ports VOR dem Import
Write-Host ""
Write-Host "Erstelle Backup-Liste der vorhandenen Drucker und Ports..." -ForegroundColor Cyan
try {
    if ($TargetServer -eq "localhost" -or $TargetServer -eq $env:COMPUTERNAME) {
        # Lokaler Server - kein ComputerName-Parameter
        $existingPrinters = Get-Printer | Select-Object -ExpandProperty Name
        $existingPorts = Get-PrinterPort | Select-Object -ExpandProperty Name
    } else {
        # Remote-Server
        $existingPrinters = Get-Printer -ComputerName $TargetServer | Select-Object -ExpandProperty Name
        $existingPorts = Get-PrinterPort -ComputerName $TargetServer | Select-Object -ExpandProperty Name
    }
    
    Write-Log "Vorhandene Drucker: $($existingPrinters.Count)" "INFO"
    Write-Log "Vorhandene Ports: $($existingPorts.Count)" "INFO"
    Write-Host "  [OK] $($existingPrinters.Count) Drucker und $($existingPorts.Count) Ports gefunden" -ForegroundColor Green
} catch {
    Write-Log "FEHLER beim Abrufen der vorhandenen Drucker/Ports: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Stacktrace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    Write-Host "Drücke eine Taste zum Beenden..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Finde alle .printerexport Dateien
$exportFiles = Get-ChildItem -Path $ExportDir -Filter "*.printerexport" | Where-Object { $_.Name -notlike "*-drivers-only*" }

if ($exportFiles.Count -eq 0) {
    Write-Log "FEHLER: Keine .printerexport Dateien gefunden!" "ERROR"
    Write-Host "  [FEHLER] Keine .printerexport Dateien gefunden!" -ForegroundColor Red
    Write-Host "  Gesuchter Pfad: $ExportDir" -ForegroundColor Yellow
    Write-Host "Drücke eine Taste zum Beenden..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""
Write-Host "Gefundene Export-Dateien: $($exportFiles.Count)" -ForegroundColor Green
foreach ($file in $exportFiles) {
    Write-Host "  - $($file.Name)" -ForegroundColor Gray
}

# Bestätigung
if (-not $SkipConfirmation) {
    Write-Host ""
    Write-Host "WARNUNG: Dieses Script wird Treiber importieren und danach NUR die importierten Drucker/Ports löschen." -ForegroundColor Yellow
    Write-Host "Vorhandene Drucker/Ports werden NICHT gelöscht." -ForegroundColor Green
    $confirmation = Read-Host "Möchten Sie fortfahren? (JA zum Fortfahren)"
    if ($confirmation -ne "JA") {
        Write-Log "Import abgebrochen durch Benutzer" "INFO"
        Write-Host "Import abgebrochen." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "=== IMPORT GESTARTET ===" -ForegroundColor Cyan
Write-Host ""

$printbrmPath = Join-Path $env:WINDIR "System32\spool\tools\Printbrm.exe"

if (-not (Test-Path $printbrmPath)) {
    Write-Log "FEHLER: Printbrm.exe nicht gefunden: $printbrmPath" "ERROR"
    Write-Host "  [FEHLER] Printbrm.exe nicht gefunden!" -ForegroundColor Red
    exit 1
}

# Importiere jede Export-Datei
foreach ($exportFile in $exportFiles) {
    $filePath = $exportFile.FullName
    $fileName = $exportFile.Name
    
    Write-Host "=== Importiere: $fileName ===" -ForegroundColor Yellow
    Write-Log "Importiere: $fileName" "INFO"
    
    try {
        # Import mit Printbrm.exe
        Write-Host "  Führe Printbrm.exe aus..." -ForegroundColor Cyan
        $importResult = & $printbrmPath -R -F $filePath -O Force 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Import erfolgreich: $fileName" "SUCCESS"
            Write-Host "  [OK] Import erfolgreich" -ForegroundColor Green
        } else {
            Write-Log "WARNUNG: Import möglicherweise fehlgeschlagen (Exit-Code: $LASTEXITCODE)" "WARNING"
            Write-Host "  [WARNUNG] Exit-Code: $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host $importResult
        }
        
    } catch {
        Write-Log "FEHLER beim Importieren von $fileName : $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Warte kurz, damit der Import abgeschlossen wird
Write-Host "Warte auf Abschluss des Imports..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

# Hole Liste der Drucker und Ports NACH dem Import
Write-Host ""
Write-Host "=== LÖSCHE NUR IMPORTIERTE DRUCKER UND PORTS ===" -ForegroundColor Cyan
Write-Host ""

try {
    if ($TargetServer -eq "localhost" -or $TargetServer -eq $env:COMPUTERNAME) {
        $allPrintersAfter = Get-Printer | Select-Object -ExpandProperty Name
        $allPortsAfter = Get-PrinterPort | Select-Object -ExpandProperty Name
    } else {
        $allPrintersAfter = Get-Printer -ComputerName $TargetServer | Select-Object -ExpandProperty Name
        $allPortsAfter = Get-PrinterPort -ComputerName $TargetServer | Select-Object -ExpandProperty Name
    }
    
    # Finde neue Drucker (die nicht vorher vorhanden waren)
    $newPrinters = @()
    foreach ($printer in $allPrintersAfter) {
        if ($printer -notin $existingPrinters) {
            $newPrinters += $printer
        }
    }
    
    # Finde neue Ports (die nicht vorher vorhanden waren)
    $newPorts = @()
    foreach ($port in $allPortsAfter) {
        if ($port -notin $existingPorts) {
            $newPorts += $port
        }
    }
    
    Write-Host "Neue Drucker (werden gelöscht): $($newPrinters.Count)" -ForegroundColor Yellow
    if ($newPrinters.Count -gt 0) {
        Write-Host "  Neue Drucker:" -ForegroundColor Gray
        foreach ($p in $newPrinters) {
            Write-Host "    - $p" -ForegroundColor Gray
        }
    }
    
    Write-Host "Neue Ports (werden gelöscht): $($newPorts.Count)" -ForegroundColor Yellow
    if ($newPorts.Count -gt 0) {
        Write-Host "  Neue Ports (erste 10):" -ForegroundColor Gray
        foreach ($p in ($newPorts | Select-Object -First 10)) {
            Write-Host "    - $p" -ForegroundColor Gray
        }
        if ($newPorts.Count -gt 10) {
            Write-Host "    ... und $($newPorts.Count - 10) weitere" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
    Write-Log "Neue Drucker gefunden: $($newPrinters.Count)" "INFO"
    Write-Log "Neue Ports gefunden: $($newPorts.Count)" "INFO"
    
    # Lösche neue Drucker (außer Microsoft-Drucker)
    $deletedPrinters = 0
    foreach ($printer in $newPrinters) {
        if ($printer -notlike "Microsoft*") {
            try {
                if ($TargetServer -eq "localhost" -or $TargetServer -eq $env:COMPUTERNAME) {
                    Remove-Printer -Name $printer -Force -ErrorAction Stop
                } else {
                    Remove-Printer -ComputerName $TargetServer -Name $printer -Force -ErrorAction Stop
                }
                Write-Log "Drucker gelöscht: $printer" "INFO"
                Write-Host "  [GELÖSCHT] Drucker: $printer" -ForegroundColor Red
                $deletedPrinters++
            } catch {
                Write-Log "FEHLER beim Löschen von Drucker $printer : $($_.Exception.Message)" "ERROR"
                Write-Host "  [FEHLER] Drucker $printer : $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Log "Microsoft-Drucker übersprungen: $printer" "INFO"
        }
    }
    
    # Lösche neue Ports (außer Standard-Ports)
    $deletedPorts = 0
    foreach ($port in $newPorts) {
        if ($port -notlike "FILE:*" -and $port -notlike "PORTPROMPT:*" -and $port -notlike "WSD:*") {
            try {
                if ($TargetServer -eq "localhost" -or $TargetServer -eq $env:COMPUTERNAME) {
                    Remove-PrinterPort -Name $port -ErrorAction Stop
                } else {
                    Remove-PrinterPort -ComputerName $TargetServer -Name $port -ErrorAction Stop
                }
                Write-Log "Port gelöscht: $port" "INFO"
                Write-Host "  [GELÖSCHT] Port: $port" -ForegroundColor Red
                $deletedPorts++
            } catch {
                Write-Log "FEHLER beim Löschen von Port $port : $($_.Exception.Message)" "ERROR"
                Write-Host "  [FEHLER] Port $port : $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Log "Standard-Port übersprungen: $port" "INFO"
        }
    }
    
    Write-Host ""
    Write-Host "=== ZUSAMMENFASSUNG ===" -ForegroundColor Cyan
    Write-Host "Gelöschte Drucker: $deletedPrinters" -ForegroundColor $(if ($deletedPrinters -gt 0) { "Yellow" } else { "Green" })
    Write-Host "Gelöschte Ports: $deletedPorts" -ForegroundColor $(if ($deletedPorts -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
    Write-Host "Vorhandene Drucker wurden NICHT gelöscht!" -ForegroundColor Green
    Write-Host ""
    
    Write-Log "Zusammenfassung: $deletedPrinters Drucker gelöscht, $deletedPorts Ports gelöscht" "INFO"
    
    # Zeige installierte Treiber
    Write-Host "=== INSTALLIERTE TREIBER ===" -ForegroundColor Cyan
    try {
        if ($TargetServer -eq "localhost" -or $TargetServer -eq $env:COMPUTERNAME) {
            $drivers = Get-PrinterDriver | Select-Object Name, PrinterEnvironment | Sort-Object Name
        } else {
            $drivers = Get-PrinterDriver -ComputerName $TargetServer | Select-Object Name, PrinterEnvironment | Sort-Object Name
        }
        Write-Host "Anzahl installierter Treiber: $($drivers.Count)" -ForegroundColor Green
        Write-Log "Anzahl installierter Treiber: $($drivers.Count)" "INFO"
    } catch {
        Write-Log "FEHLER beim Abrufen der Treiber: $($_.Exception.Message)" "ERROR"
    }
    
} catch {
    Write-Log "FEHLER beim Löschen der importierten Drucker/Ports: $($_.Exception.Message)" "ERROR"
    Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== IMPORT ABGESCHLOSSEN ===" -ForegroundColor Cyan
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Drücke eine Taste zum Beenden..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

