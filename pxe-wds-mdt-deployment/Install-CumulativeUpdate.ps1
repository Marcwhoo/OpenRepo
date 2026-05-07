# ==================================================================
# Kumulative Berechnung für Cleanup_Log.log
# Liest alle User-Log-Dateien (RoamingCleanup_*.log) und erstellt die kumulative Log-Datei
# Neueste Einträge stehen oben, kumulative Werte werden chronologisch berechnet
# ==================================================================

$HomeLogRoot = "\\<FILESERVER>\<SHARE>\<HOMEDRIVE-ROOT>\<YOUR-USERNAME>"
$LogDir = "$HomeLogRoot\Scriptlogs\Userprofile_cleaner"
$HomeLogFile = "$LogDir\Cleanup_Log.log"

if (-not (Test-Path $LogDir)) {
    Write-Host "Log-Verzeichnis nicht gefunden: $LogDir" -ForegroundColor Red
    exit 1
}

Write-Host "Suche nach User-Log-Dateien in: $LogDir" -ForegroundColor Cyan

# Alle User-Log-Dateien finden (außer Script.log)
$userLogFiles = Get-ChildItem -Path $LogDir -Filter "RoamingCleanup_*.log" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -notlike "*Script*" -and $_.Name -notlike "*Error*" }

if ($userLogFiles.Count -eq 0) {
    Write-Host "Keine User-Log-Dateien gefunden." -ForegroundColor Yellow
    exit 0
}

Write-Host "Gefundene Log-Dateien: $($userLogFiles.Count)" -ForegroundColor Green

# Alle Einträge sammeln
$entries = @()

foreach ($logFile in $userLogFiles) {
    Write-Host "Verarbeite: $($logFile.Name)" -ForegroundColor Cyan
    $lines = Get-Content -Path $logFile.FullName -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }
    
    foreach ($line in $lines) {
        # Suche nach "Cleanup abgeschlossen fuer BENUTZER – Server freigegeben: X.XXX GB"
        # Format: "2025-11-27 08:00:37 [SUCCESS] Cleanup abgeschlossen fuer benutzer – Server freigegeben: 0.123 GB, Lokal freigegeben: 0.456 GB (DryRun=False)"
        if ($line -match '^(?<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+\[SUCCESS\]\s+Cleanup abgeschlossen fuer\s+(?<benutzer>[^\s–]+)\s+–\s+Server freigegeben:\s+(?<frei>[\d.,]+)\s+GB') {
            try {
                $timestamp = [datetime]$matches['ts']
                $benutzer = $matches['benutzer'].Trim()
                $freiGB = [decimal](($matches['frei']).Replace(',', '.'))
                
                # Profilname aus Dateiname extrahieren
                $profilName = $logFile.BaseName -replace '^RoamingCleanup_', ''
                
                $entries += [PSCustomObject]@{
                    Timestamp = $timestamp
                    Benutzer = $benutzer
                    Profil = $profilName
                    FreiGB = $freiGB
                    LogFile = $logFile.Name
                }
            } catch {
                Write-Host "Fehler beim Parsen der Zeile: $line - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

if ($entries.Count -eq 0) {
    Write-Host "Keine gültigen Cleanup-Einträge in den Log-Dateien gefunden." -ForegroundColor Yellow
    exit 0
}

Write-Host "Gefundene Cleanup-Einträge: $($entries.Count)" -ForegroundColor Green

# Nach Zeitstempel sortieren (älteste zuerst für kumulative Berechnung)
$sortedEntries = $entries | Sort-Object -Property Timestamp

# Kumulative Summe berechnen
$kumulativ = 0
$newLines = @()

foreach ($entry in $sortedEntries) {
    $kumulativ += $entry.FreiGB
    $newLine = "$($entry.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) | $($entry.Benutzer) | $($entry.Profil) | $($entry.FreiGB) GB | Kumulativ: $([math]::Round($kumulativ, 3)) GB"
    $newLines += $newLine
}

# Umkehren, damit neueste Einträge oben stehen
$newLines = $newLines | Sort-Object -Descending

# Alte Log-Datei loeschen (falls vorhanden)
if (Test-Path $HomeLogFile) {
    try {
        Remove-Item -Path $HomeLogFile -Force -ErrorAction Stop
        Write-Host "Alte Log-Datei geloescht: $HomeLogFile" -ForegroundColor Yellow
    } catch {
        Write-Host "Warnung: Alte Log-Datei konnte nicht geloescht werden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Komplett neue Datei erstellen
try {
    $newLines | Out-File -FilePath $HomeLogFile -Encoding UTF8 -Force
    Write-Host "Kumulative Log-Datei neu erstellt: $HomeLogFile" -ForegroundColor Green
    Write-Host "Gesamt kumulativ: $([math]::Round($kumulativ, 3)) GB" -ForegroundColor Cyan
    Write-Host "Eintraege: $($entries.Count)" -ForegroundColor Cyan
} catch {
    Write-Host "Fehler beim Schreiben der Datei: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Fertig!" -ForegroundColor Green
