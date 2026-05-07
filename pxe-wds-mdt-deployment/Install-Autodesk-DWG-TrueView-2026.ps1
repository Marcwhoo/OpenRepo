# ==================================================================
# Install-Autodesk-DWG-TrueView-2026.ps1
# Führt die stille Installation von Autodesk DWG TrueView 2026 durch
# 
# Dieses Skript:
# 1. Findet das extrahierte Installationsverzeichnis
# 2. Modifiziert setup.ini für deutsche Sprache (falls vorhanden)
# 3. Führt die stille Installation mit Setup.exe durch
# 
# Verwendung:
# - Führen Sie zuerst Extract-Autodesk-DWG-TrueView-2026.ps1 aus
# - Oder geben Sie den extrahierten Pfad als Parameter an: .\Install-Autodesk-DWG-TrueView-2026.ps1 -ExtractedPath "C:\Pfad\..."
# ==================================================================

param(
    [string]$ExtractedPath = ""
)

$ErrorActionPreference = "Continue"
# Unterdrücke alle Ausgaben
$ProgressPreference = "SilentlyContinue"

# Konfiguration
$LogDir = "C:\EDV\AutoCAD"
$LogFile = Join-Path $LogDir "Install-DWG-TrueView-2026_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
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
                    Write-Log "Englische Version gefunden: $path (wird mit /language de-de Parameter überschrieben)" "INFO"
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

Write-Log "=== Starte Installation von Autodesk DWG TrueView 2026 ==="
Write-Log "Benutzer: $env:USERNAME"
Write-Log "Computer: $env:COMPUTERNAME"

# Finde extrahiertes Verzeichnis
$extractedPath = $null

if (-not [string]::IsNullOrEmpty($ExtractedPath)) {
    # Pfad wurde als Parameter übergeben
    if (Test-Path $ExtractedPath) {
        $setupExe = Join-Path $ExtractedPath "Setup.exe"
        if (Test-Path $setupExe) {
            $extractedPath = $ExtractedPath
            Write-Log "Extrahiertes Verzeichnis aus Parameter: $extractedPath" "INFO"
        } else {
            Write-Log "FEHLER: Setup.exe nicht gefunden in: $ExtractedPath" "ERROR"
            exit 1
        }
    } else {
        Write-Log "FEHLER: Verzeichnis nicht gefunden: $ExtractedPath" "ERROR"
        exit 1
    }
} elseif (Test-Path $ExtractedPathFile) {
    # Pfad aus Datei lesen
    try {
        $extractedPath = Get-Content $ExtractedPathFile -ErrorAction SilentlyContinue
        if ($extractedPath -and (Test-Path $extractedPath)) {
            $setupExe = Join-Path $extractedPath "Setup.exe"
            if (Test-Path $setupExe) {
                Write-Log "Extrahiertes Verzeichnis aus Datei gelesen: $extractedPath" "INFO"
            } else {
                Write-Log "WARNUNG: Setup.exe nicht gefunden in gespeichertem Pfad, suche neu..." "WARN"
                $extractedPath = $null
            }
        } else {
            Write-Log "WARNUNG: Gespeicherter Pfad ungültig, suche neu..." "WARN"
            $extractedPath = $null
        }
    } catch {
        Write-Log "WARNUNG: Konnte Pfad aus Datei nicht lesen, suche neu..." "WARN"
        $extractedPath = $null
    }
}

# Falls noch nicht gefunden, suche automatisch
if ($null -eq $extractedPath) {
    Write-Log "Suche nach extrahiertem Verzeichnis..."
    $extractedPath = Find-ExtractedPath
}

if ($null -eq $extractedPath) {
    Write-Log "FEHLER: Extrahiertes Verzeichnis nicht gefunden" "ERROR"
    Write-Log "Bitte führen Sie zuerst Extract-Autodesk-DWG-TrueView-2026.ps1 aus" "ERROR"
    Write-Log "Oder geben Sie den Pfad als Parameter an: .\Install-Autodesk-DWG-TrueView-2026.ps1 -ExtractedPath 'C:\Pfad\...'" "ERROR"
    exit 1
}

$SetupExe = Join-Path $extractedPath "Setup.exe"
Write-Log "Setup.exe gefunden: $SetupExe"

# Prüfe Sprache des extrahierten Verzeichnisses
$isGermanPath = ($extractedPath -match "(Deutsch|German)" -or $extractedPath -match "\(DE\)" -or $extractedPath -match "- DE")
$isEnglishPath = ($extractedPath -match "English" -or $extractedPath -match "\(EN\)" -or $extractedPath -match "- EN")

if ($isGermanPath -and -not $isEnglishPath) {
    Write-Log "Deutsche Version wird installiert: $extractedPath" "SUCCESS"
} elseif ($isEnglishPath) {
    Write-Log "Englische Version gefunden: $extractedPath" "INFO"
    Write-Log "Sprache wird durch /language de-de Parameter auf Deutsch gesetzt" "INFO"
} else {
    Write-Log "Version gefunden: $extractedPath (Sprache unbekannt)" "INFO"
    Write-Log "Sprache wird durch /language de-de Parameter auf Deutsch gesetzt" "INFO"
}

# Prüfe ob setup.xml existiert (wird für ODIS benötigt)
$setupXml = Join-Path $extractedPath "setup.xml"
if (Test-Path $setupXml) {
    Write-Log "setup.xml gefunden: $setupXml"
} else {
    Write-Log "WARNUNG: setup.xml nicht gefunden, Installation könnte fehlschlagen" "WARN"
}

# Schritt 2: Führe Silent-Installation durch
Write-Log "Starte Silent-Installation mit Setup.exe..."

# Prüfe ob setup.ini existiert und kann modifiziert werden
$setupIni = Join-Path $extractedPath "setup.ini"
$setupIniModified = $false

if (Test-Path $setupIni) {
    Write-Log "setup.ini gefunden: $setupIni"
    try {
        # Versuche setup.ini zu modifizieren, um Sprache auf Deutsch zu setzen
        $iniContent = Get-Content $setupIni -Raw -ErrorAction SilentlyContinue
        if ($iniContent -and $iniContent -notmatch "\[LANGUAGE\]") {
            # Füge Sprachabschnitt hinzu, falls nicht vorhanden
            $iniContent += "`r`n[LANGUAGE]`r`nLANG=de-DE`r`n"
            Set-Content -Path $setupIni -Value $iniContent -Encoding UTF8 -NoNewline -ErrorAction SilentlyContinue
            $setupIniModified = $true
            Write-Log "setup.ini wurde modifiziert: Sprache auf de-DE gesetzt" "INFO"
        } elseif ($iniContent -match "\[LANGUAGE\]") {
            # Sprachabschnitt existiert bereits, versuche zu ändern
            $iniContent = $iniContent -replace "LANG=.*", "LANG=de-DE"
            Set-Content -Path $setupIni -Value $iniContent -Encoding UTF8 -NoNewline -ErrorAction SilentlyContinue
            $setupIniModified = $true
            Write-Log "setup.ini wurde modifiziert: Sprache auf de-DE geändert" "INFO"
        }
    } catch {
        Write-Log "WARNUNG: setup.ini konnte nicht modifiziert werden: $_" "WARN"
    }
}

try {
    # Parameter für deutsche Installation:
    # -q = Quiet/Silent Mode (kleingeschrieben funktioniert besser)
    # /language de-de = Erzwingt deutsche Sprache
    # Falls setup.ini modifiziert wurde, verwende /i setup.ini
    if ($setupIniModified -and (Test-Path $setupIni)) {
        $setupArgs = @(
            "-q",              # Quiet mode
            "/i", "setup.ini"   # Verwende modifizierte setup.ini
        )
        Write-Log "Parameter: -q /i setup.ini (mit modifizierter setup.ini für Deutsch)" "INFO"
    } else {
        $setupArgs = @(
            "-q",              # Quiet mode
            "/language", "de-de"  # Deutsche Sprache erzwingen
        )
        Write-Log "Parameter: -q /language de-de (quiet installation, Deutsch erzwingen)" "INFO"
    }
    
    Write-Log "Führe Setup.exe aus mit Parametern: $($setupArgs -join ' ')"
    Write-Log "Dies kann einige Minuten dauern..."
    
    $setupProcess = Start-Process -FilePath $SetupExe -ArgumentList $setupArgs -Wait -PassThru -WindowStyle Hidden
    
    Write-Log "Installation beendet mit Exit-Code: $($setupProcess.ExitCode)"
    
    if ($setupProcess.ExitCode -eq 0) {
        Write-Log "Installation erfolgreich abgeschlossen (Exit-Code: 0)" "SUCCESS"
        Write-Log "Deutsche Version wurde installiert" "SUCCESS"
    } elseif ($setupProcess.ExitCode -eq 3010) {
        # Exit-Code 3010 = Erfolgreich, Neustart erforderlich
        Write-Log "Installation erfolgreich abgeschlossen (Exit-Code: 3010)" "SUCCESS"
        Write-Log "Deutsche Version wurde installiert" "SUCCESS"
        Write-Log "HINWEIS: Ein Neustart wird empfohlen" "INFO"
    } else {
        Write-Log "FEHLER: Installation fehlgeschlagen mit Exit-Code: $($setupProcess.ExitCode)" "ERROR"
        Write-Log "Bitte prüfen Sie die Installationsprotokolle" "ERROR"
        exit 1
    }
} catch {
    Write-Log "FEHLER bei der Installation: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

Write-Log "=== Installation von Autodesk DWG TrueView 2026 abgeschlossen ==="

# Optional: Prüfe ob Installation erfolgreich war
Write-Log "Verifiziere Installation..."
$possibleInstallPaths = @(
    "C:\Program Files\Autodesk\DWG TrueView 2026",
    "C:\Program Files (x86)\Autodesk\DWG TrueView 2026",
    "C:\Program Files\Autodesk\DWG TrueView 2026 - Deutsch",
    "C:\Program Files\Autodesk\DWG TrueView 2026 - English"
)

$installationFound = $false
foreach ($installPath in $possibleInstallPaths) {
    if (Test-Path $installPath) {
        Write-Log "Installation erfolgreich verifiziert: $installPath" "SUCCESS"
        $installationFound = $true
        
        # Prüfe nach ausführbarer Datei
        $exeFiles = Get-ChildItem -Path $installPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*dwgview*" -or $_.Name -like "*trueview*" }
        if ($exeFiles) {
            Write-Log "Hauptprogramm gefunden: $($exeFiles[0].FullName)" "SUCCESS"
        }
        break
    }
}

if (-not $installationFound) {
    Write-Log "WARNUNG: Installationsverzeichnis nicht gefunden" "WARN"
    Write-Log "Die Installation könnte trotzdem erfolgreich gewesen sein" "WARN"
    Write-Log "Bitte prüfen Sie manuell im Startmenü oder in 'Programme hinzufügen/entfernen'" "WARN"
}

# Aufräumen: Lösche Extraktionsordner und C:\EDV\AutoCAD
# WICHTIG: Diese Funktion wird immer ausgeführt, auch bei Fehlern
# Fehler beim Löschen führen NICHT zum Beenden des Skripts
Write-Log "Starte Aufräumen: Lösche temporäre Dateien und Ordner..."

# 1. Lösche Extraktionsordner
if ($extractedPath -and (Test-Path $extractedPath)) {
    try {
        Write-Log "Lösche Extraktionsordner: $extractedPath"
        $null = Remove-Item -Path $extractedPath -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        if (-not (Test-Path $extractedPath)) {
            Write-Log "Extraktionsordner erfolgreich gelöscht" "SUCCESS"
        } else {
            Write-Log "INFO: Extraktionsordner konnte nicht gelöscht werden (möglicherweise in Verwendung)" "INFO"
        }
    } catch {
        # Fehler wird ignoriert - Skript wird nicht beendet
        Write-Log "INFO: Extraktionsordner konnte nicht gelöscht werden: $_" "INFO"
    }
} else {
    Write-Log "INFO: Extraktionsordner nicht gefunden oder bereits gelöscht" "INFO"
}

# 2. Lösche C:\EDV\AutoCAD (aber nur wenn es existiert und nicht mehr benötigt wird)
$autocadDir = "C:\EDV\AutoCAD"
if (Test-Path $autocadDir) {
    try {
        Write-Log "Lösche Verzeichnis: $autocadDir"
        
        # Versuche alle Dateien und Unterordner zu löschen
        $null = Get-ChildItem -Path $autocadDir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Versuche das Verzeichnis selbst zu löschen
        $null = Remove-Item -Path $autocadDir -Force -Recurse -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        
        if (-not (Test-Path $autocadDir)) {
            Write-Log "Verzeichnis C:\EDV\AutoCAD erfolgreich gelöscht" "SUCCESS"
        } else {
            Write-Log "INFO: Verzeichnis C:\EDV\AutoCAD konnte nicht gelöscht werden (möglicherweise in Verwendung)" "INFO"
        }
    } catch {
        # Fehler wird ignoriert - Skript wird nicht beendet
        Write-Log "INFO: Verzeichnis C:\EDV\AutoCAD konnte nicht gelöscht werden: $_" "INFO"
    }
} else {
    Write-Log "INFO: Verzeichnis C:\EDV\AutoCAD existiert nicht oder wurde bereits gelöscht" "INFO"
}

# 3. Lösche auch die Pfad-Datei, falls vorhanden
if (Test-Path $ExtractedPathFile) {
    try {
        $null = Remove-Item -Path $ExtractedPathFile -Force -ErrorAction SilentlyContinue
        Write-Log "Pfad-Datei gelöscht: $ExtractedPathFile" "INFO"
    } catch {
        # Fehler wird ignoriert - Skript wird nicht beendet
        Write-Log "INFO: Pfad-Datei konnte nicht gelöscht werden: $_" "INFO"
    }
}

Write-Log "Aufräumen abgeschlossen"
Write-Log "Log-Datei: $LogFile"
Write-Log "=== Skript beendet ==="

# Skript beenden
exit 0
