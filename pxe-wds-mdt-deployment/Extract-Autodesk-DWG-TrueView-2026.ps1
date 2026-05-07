# ==================================================================
# Extract-Autodesk-DWG-TrueView-2026.ps1
# Extrahiert die Installationsdateien von Autodesk DWG TrueView 2026
# 
# Dieses Skript:
# 1. Extrahiert die Installationsdateien mit DWG TrueView 2026.exe
# 2. Wartet auf Abschluss der Extraktion
# 3. Speichert den extrahierten Pfad in eine Datei
# 
# Installationsdatei:
# - Pfad: C:\EDV\AutoCAD\DWG TrueView 2026.exe
# ==================================================================

$ErrorActionPreference = "SilentlyContinue"
# Unterdrücke alle Ausgaben
$ProgressPreference = "SilentlyContinue"

# Konfiguration
$InstallerPath = "C:\EDV\AutoCAD\DWG TrueView 2026.exe"
$LogDir = "C:\EDV\AutoCAD"
$LogFile = Join-Path $LogDir "Extract-DWG-TrueView-2026_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
$ExtractedPathFile = Join-Path $LogDir "DWG-TrueView-2026-ExtractedPath.txt"

# Erstelle Log-Verzeichnis
if (-not (Test-Path $LogDir)) { 
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null 
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    # Keine Ausgabe auf Konsole - nur Logging in Datei
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Find-ExtractedPath {
    # Suche nach dem extrahierten Installationsverzeichnis
    # Standardpfad: C:\Users\[Benutzername]\Downloads\Autodesk\DWG TrueView 2026 - [Sprache]
    
    # Deutsche Versionen ZUERST (Priorität)
    $germanPaths = @(
        "$env:USERPROFILE\Downloads\Autodesk\DWG TrueView 2026 - Deutsch - (DE)",
        "$env:USERPROFILE\Downloads\Autodesk\DWG TrueView 2026 - German",
        "C:\Autodesk\DWG TrueView 2026 - Deutsch - (DE)",
        "C:\Autodesk\DWG TrueView 2026 - German"
    )
    
    # Andere Sprachen (Fallback)
    $otherPaths = @(
        "$env:USERPROFILE\Downloads\Autodesk\DWG TrueView 2026 - English - (EN)",
        "C:\Autodesk\DWG TrueView 2026 - English - (EN)"
    )
    
    # Suche auch dynamisch im Autodesk-Ordner
    $autodeskBasePath = "$env:USERPROFILE\Downloads\Autodesk"
    $foundDirs = @()
    
    if (Test-Path $autodeskBasePath) {
        $allDirs = Get-ChildItem -Path $autodeskBasePath -Directory -Filter "*DWG TrueView 2026*" -ErrorAction SilentlyContinue
        foreach ($dir in $allDirs) {
            # Sortiere: Deutsche Versionen zuerst
            if ($dir.Name -match "(Deutsch|German|DE)") {
                $foundDirs = @($dir.FullName) + $foundDirs
            } else {
                $foundDirs += $dir.FullName
            }
        }
    }
    
    # Kombiniere alle Pfade: Deutsche zuerst, dann andere, dann gefundene
    $allPaths = $germanPaths + $otherPaths + $foundDirs
    
    # Entferne Duplikate
    $uniquePaths = $allPaths | Select-Object -Unique
    
    $foundPath = $null
    
    foreach ($path in $uniquePaths) {
        $setupExe = Join-Path $path "Setup.exe"
        if (Test-Path $setupExe) {
            # Prüfe explizit auf deutsche Version (nicht auf "EN" in "English")
            $isGerman = ($path -match "(Deutsch|German)" -or $path -match "\(DE\)" -or $path -match "- DE")
            $isEnglish = ($path -match "English" -or $path -match "\(EN\)" -or $path -match "- EN")
            
            if ($isGerman -and -not $isEnglish) {
                Write-Log "Deutsche Version gefunden: $path" "SUCCESS"
                return $path
            } elseif ($null -eq $foundPath) {
                # Merke erste gefundene Version als Fallback
                if ($isEnglish) {
                    Write-Log "Englische Version gefunden: $path" "INFO"
                } else {
                    Write-Log "Version gefunden: $path (Sprache unbekannt)" "INFO"
                }
                $foundPath = $path
            }
        }
    }
    
    # Wenn deutsche Version nicht gefunden, aber andere Version vorhanden
    if ($null -ne $foundPath) {
        Write-Log "Version gefunden: $foundPath" "INFO"
        return $foundPath
    }
    
    return $null
}

Write-Log "=== Starte Extraktion von Autodesk DWG TrueView 2026 ==="
Write-Log "Benutzer: $env:USERNAME"
Write-Log "Computer: $env:COMPUTERNAME"

# Prüfe ob Installer existiert
if (-not (Test-Path $InstallerPath)) {
    Write-Log "FEHLER: Installer nicht gefunden: $InstallerPath" "ERROR"
    Write-Log "Bitte stellen Sie sicher, dass die Installationsdatei im Verzeichnis C:\EDV\AutoCAD liegt" "ERROR"
    
    # Prüfe ob Verzeichnis existiert
    $installerDir = Split-Path $InstallerPath -Parent
    if (-not (Test-Path $installerDir)) {
        Write-Log "FEHLER: Installationsverzeichnis existiert nicht: $installerDir" "ERROR"
        Write-Log "Bitte erstellen Sie das Verzeichnis und legen Sie die Installationsdatei dort ab" "ERROR"
    } else {
        Write-Log "Verzeichnis existiert, aber Datei 'DWG TrueView 2026.exe' nicht gefunden" "ERROR"
        Write-Log "Verfügbare Dateien im Verzeichnis:" "INFO"
        Get-ChildItem -Path $installerDir -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "  - $($_.Name)" "INFO"
        }
    }
    exit 1
}

Write-Log "Installer gefunden: $InstallerPath"
$installerInfo = Get-Item $InstallerPath
Write-Log "Installer-Größe: $([math]::Round($installerInfo.Length / 1MB, 2)) MB"

# Schritt 1: Extrahiere Installationsdateien (silent extraction)
Write-Log "Extrahiere Installationsdateien mit DWG TrueView 2026.exe..."
Write-Log "Parameter: -q (quiet/silent extraction)"

try {
    Write-Log "Starte Extraktionsprozess..."
    
    # Starte Extraktion - der Installer startet oft einen separaten Prozess
    $extractProcess = Start-Process -FilePath $InstallerPath -ArgumentList "-q" -PassThru -WindowStyle Hidden
    
    Write-Log "Extraktionsprozess gestartet (PID: $($extractProcess.Id))"
    Write-Log "HINWEIS: Der Installer startet möglicherweise einen separaten Prozess" "INFO"
    Write-Log "Warte auf Abschluss der Extraktion (dies kann mehrere Minuten dauern)..." "INFO"
    
    # Warte kurz, damit der Installer starten kann
    Start-Sleep -Seconds 3
    
    # Suche nach laufenden Prozessen, die mit dem Installer zusammenhängen
    $installerName = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath)
    $relatedProcesses = Get-Process | Where-Object { 
        $_.ProcessName -like "*$installerName*" -or 
        $_.ProcessName -like "*DWG*" -or 
        $_.ProcessName -like "*TrueView*" -or
        $_.ProcessName -like "*Autodesk*"
    } | Select-Object -First 5
    
    if ($relatedProcesses) {
        Write-Log "Gefundene laufende Prozesse:" "INFO"
        foreach ($proc in $relatedProcesses) {
            Write-Log "  - $($proc.ProcessName) (PID: $($proc.Id))" "INFO"
        }
    }
    
    # Warte auf Prozess-Ende mit Timeout
    $maxWaitTime = 30 # 30 Sekunden für den Hauptprozess
    $waitInterval = 1 # 1 Sekunde
    $elapsed = 0
    $processEnded = $false
    
    while ($elapsed -lt $maxWaitTime -and -not $processEnded) {
        Start-Sleep -Seconds $waitInterval
        $elapsed += $waitInterval
        
        # Prüfe ob Hauptprozess noch läuft
        try {
            $runningProcess = Get-Process -Id $extractProcess.Id -ErrorAction SilentlyContinue
            if (-not $runningProcess) {
                $processEnded = $true
                Write-Log "Hauptprozess beendet nach $elapsed Sekunden"
            }
        } catch {
            # Prozess existiert nicht mehr
            $processEnded = $true
            Write-Log "Hauptprozess beendet nach $elapsed Sekunden"
        }
    }
    
    if (-not $processEnded) {
        Write-Log "Hauptprozess läuft noch, aber Extraktion könnte im Hintergrund laufen" "INFO"
    }
    
    Write-Log "Extraktion gestartet - warte auf Erscheinen der Setup.exe..." "INFO"
    
} catch {
    Write-Log "FEHLER beim Starten der Extraktion: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

# Warte auf Extraktion und suche nach Setup.exe
Write-Log "Warte auf Abschluss der Extraktion und suche nach Setup.exe..."
$maxWaitTime = 300 # 5 Minuten
$waitInterval = 5 # 5 Sekunden
$elapsed = 0
$extractedPath = $null

while ($elapsed -lt $maxWaitTime -and $null -eq $extractedPath) {
    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
    $extractedPath = Find-ExtractedPath
    
    if ($null -eq $extractedPath) {
        Write-Log "Warte auf Extraktion... ($elapsed / $maxWaitTime Sekunden)"
    }
}

if ($null -eq $extractedPath) {
    Write-Log "FEHLER: Setup.exe nicht gefunden nach $maxWaitTime Sekunden" "ERROR"
    Write-Log "Bitte prüfen Sie manuell, ob die Extraktion erfolgreich war" "ERROR"
    Write-Log "Erwarteter Pfad: $env:USERPROFILE\Downloads\Autodesk\DWG TrueView 2026 - [Sprache]" "ERROR"
    exit 1
}

$SetupExe = Join-Path $extractedPath "Setup.exe"
Write-Log "Setup.exe gefunden: $SetupExe"

# Prüfe Sprache des extrahierten Verzeichnisses
$isGermanPath = ($extractedPath -match "(Deutsch|German)" -or $extractedPath -match "\(DE\)" -or $extractedPath -match "- DE")
$isEnglishPath = ($extractedPath -match "English" -or $extractedPath -match "\(EN\)" -or $extractedPath -match "- EN")

if ($isGermanPath -and -not $isEnglishPath) {
    Write-Log "Deutsche Version extrahiert: $extractedPath" "SUCCESS"
} elseif ($isEnglishPath) {
    Write-Log "Englische Version extrahiert: $extractedPath" "INFO"
} else {
    Write-Log "Version extrahiert: $extractedPath (Sprache unbekannt)" "INFO"
}

# Speichere extrahierten Pfad in Datei
try {
    Set-Content -Path $ExtractedPathFile -Value $extractedPath -Encoding UTF8
    Write-Log "Extrahierten Pfad gespeichert: $ExtractedPathFile" "SUCCESS"
} catch {
    Write-Log "WARNUNG: Konnte extrahierten Pfad nicht speichern: $_" "WARN"
}

Write-Log "=== Extraktion von Autodesk DWG TrueView 2026 abgeschlossen ==="
Write-Log "Extrahiertes Verzeichnis: $extractedPath"
Write-Log "Log-Datei: $LogFile"
Write-Log "Extrahierten Pfad gespeichert in: $ExtractedPathFile"
Write-Log "=== Skript beendet ==="

# Skript beenden
exit 0

