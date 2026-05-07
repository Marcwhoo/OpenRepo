# ==================================================================
# Profilgroessen-Analyse
# Durchsucht alle Profile auf dem Server und listet sie nach Groesse sortiert auf
# ==================================================================

$ServerRoot = "\\<DOMAIN-FQDN>\<SHARE>"
$HomeLogRoot = "\\<FILESERVER>\<SHARE>\<HOMEDRIVE-ROOT>\<YOUR-USERNAME>"
$LogDir = "$HomeLogRoot\Scriptlogs\Userprofile_cleaner"
$LogFile = "$LogDir\Profilgroessen_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

$AdditionalProfileRoots = @(
    "$ServerRoot\<PROFILE-FOLDER>"
)

$ErrorActionPreference = "Continue"

Write-Host "=== Profilgroessen-Analyse gestartet ===" -ForegroundColor Cyan
Write-Host "Server-Root: $ServerRoot" -ForegroundColor Yellow
Write-Host "Log-Datei: $LogFile" -ForegroundColor Yellow

# Pruefe Log-Verzeichnis
if (-not (Test-Path $LogDir)) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null
        Write-Host "Log-Verzeichnis erstellt: $LogDir" -ForegroundColor Green
    }
    catch {
        Write-Host "FEHLER: Log-Verzeichnis konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Get-DirectorySizeGB {
    param(
        [string]$Path,
        [string]$Name
    )
    
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    Write-Host "Berechne Groesse: $Name" -ForegroundColor Gray
    
    try {
        $size = 0
        $fileCount = 0
        
        # Methode 1: Robocopy (genaueste Methode fuer Netzwerkpfade)
        try {
            $tempFile = [System.IO.Path]::GetTempFileName()
            robocopy $Path $Path /L /NJH /NJS /S /BYTES /R:0 /W:0 2>&1 | Out-File -FilePath $tempFile
            
            # Parse robocopy output - suche nach "Bytes" in der letzten Zeile
            $robocopyContent = Get-Content $tempFile -ErrorAction SilentlyContinue
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            # Robocopy gibt die Gesamtgroesse in der letzten Zeile aus
            # Format: "Total    Copied   Skipped  Mismatch    FAILED    Extras"
            #         "Dirs :         1         0         1         0         0         0"
            #         "Files :    12345     12345         0         0         0         0"
            #         "Bytes : 1234567890 1234567890         0         0         0         0"
            $bytesLine = $robocopyContent | Where-Object { $_ -match 'Bytes\s*:\s*\d+\s+\d+' } | Select-Object -Last 1
            if ($bytesLine -match 'Bytes\s*:\s*(\d+)\s+(\d+)') {
                # Erste Zahl ist Gesamtgroesse, zweite ist kopierte Groesse
                $size = [long]$matches[1]
            }
            
            if ($size -gt 0) {
                # Dateianzahl mit Get-ChildItem ermitteln (schneller)
                try {
                    $fileCount = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                }
                catch {
                    # Ignoriere Fehler bei Dateianzahl
                }
            }
        }
        catch {
            # Robocopy fehlgeschlagen, versuche andere Methode
        }
        
        # Methode 2: COM-Objekt (wenn robocopy nicht funktioniert hat)
        if ($size -eq 0) {
            try {
                $fso = New-Object -ComObject Scripting.FileSystemObject
                $folder = $fso.GetFolder($Path)
                $size = $folder.Size
                $fileCount = $folder.Files.Count
            }
            catch {
                # COM-Objekt fehlgeschlagen
            }
        }
        
        # Methode 3: Get-ChildItem (Fallback)
        if ($size -eq 0) {
            Write-Host "  Verwende Get-ChildItem-Methode fuer $Name..." -ForegroundColor DarkYellow
            
            try {
                $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
                $fileCount = ($files | Measure-Object).Count
                
                foreach ($file in $files) {
                    try {
                        if ($null -ne $file -and $null -ne $file.Length) {
                            $size += $file.Length
                        }
                    }
                    catch {
                        # Ignoriere einzelne Fehler
                    }
                }
            }
            catch {
                Write-Host "  FEHLER bei Get-ChildItem-Methode fuer $Name : $($_.Exception.Message)" -ForegroundColor Red
                return $null
            }
        }
        
        # Finale Pruefung
        if ($size -eq 0) {
            $hasContent = (Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
            if ($hasContent) {
                Write-Host "  Warnung: $Name scheint Inhalt zu haben, aber Groesse ist 0" -ForegroundColor Yellow
            }
        }
        
        $sizeGB = [math]::Round($size / 1GB, 3)
        Write-Host "  $Name : $sizeGB GB ($fileCount Dateien)" -ForegroundColor DarkGray
        return $sizeGB
    }
    catch {
        Write-Host "KRITISCHER FEHLER beim Berechnen der Groesse fuer $Name : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-ProfileDirectories {
    $profileDirs = @()
    
    # Haupt-Server-Root durchsuchen
    Write-Host "Durchsuche Server-Root: $ServerRoot" -ForegroundColor Cyan
    try {
        if (Test-Path $ServerRoot) {
            $profileFolders = Get-ChildItem -Path $ServerRoot -Directory -ErrorAction SilentlyContinue | 
                              Where-Object { $_.Name -like "Profile*" }
            
            Write-Host "  Gefundene Profile-Ordner: $($profileFolders.Count)" -ForegroundColor Gray
            
            foreach ($folder in $profileFolders) {
                Write-Host "  Durchsuche: $($folder.Name)" -ForegroundColor Gray
                try {
                    $subDirs = Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue
                    Write-Host "    Gefundene Profile: $($subDirs.Count)" -ForegroundColor DarkGray
                    foreach ($subDir in $subDirs) {
                        $profileDirs += [PSCustomObject]@{
                            Path = $subDir.FullName
                            Name = $subDir.Name
                            Root = $folder.Name
                        }
                    }
                }
                catch {
                    Write-Host "    FEHLER beim Durchsuchen von $($folder.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        else {
            Write-Host "  WARNUNG: Server-Root nicht erreichbar: $ServerRoot" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "FEHLER beim Durchsuchen von $ServerRoot : $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Zusaetzliche Profile-Roots durchsuchen
    foreach ($extraRoot in $AdditionalProfileRoots) {
        Write-Host "Durchsuche zusaetzliches Root: $extraRoot" -ForegroundColor Cyan
        try {
            if (Test-Path $extraRoot) {
                $subDirs = Get-ChildItem -Path $extraRoot -Directory -ErrorAction SilentlyContinue
                Write-Host "  Gefundene Profile: $($subDirs.Count)" -ForegroundColor Gray
                foreach ($subDir in $subDirs) {
                    $profileDirs += [PSCustomObject]@{
                        Path = $subDir.FullName
                        Name = $subDir.Name
                        Root = Split-Path $extraRoot -Leaf
                    }
                }
            }
            else {
                Write-Host "  WARNUNG: Zusaetzliches Root nicht erreichbar: $extraRoot" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "FEHLER beim Durchsuchen von $extraRoot : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "Gesamt gefundene Profile-Verzeichnisse: $($profileDirs.Count)" -ForegroundColor Green
    return $profileDirs
}

# Alle Profile-Verzeichnisse finden
Write-Host ""
Write-Host "Suche nach Profile-Verzeichnissen..." -ForegroundColor Cyan
$profileDirectories = Get-ProfileDirectories

if ($profileDirectories.Count -eq 0) {
    Write-Host "KEINE Profile-Verzeichnisse gefunden!" -ForegroundColor Red
    exit 1
}

Write-Host "Gefundene Profile: $($profileDirectories.Count)" -ForegroundColor Green

# Debug: Pruefe ob bestimmte Profile gefunden wurden
$testProfiles = @("steiner", "hobrecht", "cetinay")
foreach ($testProfile in $testProfiles) {
    $found = $profileDirectories | Where-Object { $_.Name -like "*$testProfile*" }
    if ($found) {
        Write-Host "  [DEBUG] Gefunden: $($found.Name) in $($found.Root)" -ForegroundColor DarkGreen
    }
    else {
        Write-Host "  [DEBUG] NICHT gefunden: $testProfile" -ForegroundColor DarkYellow
    }
}

Write-Host ""

# Groesse fuer jedes Profil berechnen
$profileSizes = @()
$processed = 0

foreach ($profileItem in $profileDirectories) {
    $processed++
    Write-Host "[$processed/$($profileDirectories.Count)] Verarbeite: $($profileItem.Name)" -ForegroundColor Yellow
    
    $sizeGB = Get-DirectorySizeGB -Path $profileItem.Path -Name $profileItem.Name
    
    if ($null -ne $sizeGB) {
        $profileSizes += [PSCustomObject]@{
            Name = $profileItem.Name
            Path = $profileItem.Path
            Root = $profileItem.Root
            SizeGB = $sizeGB
        }
    }
}

# Nach Groesse sortieren (groesste zuerst)
$sortedProfiles = $profileSizes | Sort-Object -Property SizeGB -Descending

# Log-Datei erstellen
Write-Host ""
Write-Host "Erstelle Log-Datei..." -ForegroundColor Cyan

$logContent = @()
$logContent += "=================================================================="
$logContent += "Profilgroessen-Analyse"
$logContent += "Erstellt am: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$logContent += "Server-Root: $ServerRoot"
$logContent += "Gefundene Profile: $($sortedProfiles.Count)"
$logContent += "=================================================================="
$logContent += ""
$logContent += "Format: Groesse (GB) | Profilname | Root-Verzeichnis | Vollstaendiger Pfad"
$logContent += ""

$totalSize = 0

foreach ($profileItem in $sortedProfiles) {
    $totalSize += $profileItem.SizeGB
    $line = "$($profileItem.SizeGB.ToString('0.000')) GB | $($profileItem.Name) | $($profileItem.Root) | $($profileItem.Path)"
    $logContent += $line
}

$logContent += ""
$logContent += "=================================================================="
$logContent += "Gesamtgroesse aller Profile: $([math]::Round($totalSize, 3)) GB"
$logContent += "Anzahl Profile: $($sortedProfiles.Count)"
$logContent += "Durchschnittliche Profilgroesse: $([math]::Round($totalSize / $sortedProfiles.Count, 3)) GB"
$logContent += "=================================================================="

# Top 10 groesste Profile
$logContent += ""
$logContent += "--- Top 10 groesste Profile ---"
$top10 = $sortedProfiles | Select-Object -First 10
$rank = 1
foreach ($profileItem in $top10) {
    $logContent += "$rank. $($profileItem.Name): $($profileItem.SizeGB.ToString('0.000')) GB ($($profileItem.Root))"
    $rank++
}

# Log-Datei schreiben
try {
    $logContent | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    Write-Host "Log-Datei erstellt: $LogFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
    Write-Host "Gesamtgroesse: $([math]::Round($totalSize, 3)) GB" -ForegroundColor Green
    Write-Host "Anzahl Profile: $($sortedProfiles.Count)" -ForegroundColor Green
    Write-Host "Durchschnitt: $([math]::Round($totalSize / $sortedProfiles.Count, 3)) GB" -ForegroundColor Green
    Write-Host ""
    Write-Host "Top 5 groesste Profile:" -ForegroundColor Yellow
    $top5 = $sortedProfiles | Select-Object -First 5
    foreach ($profileItem in $top5) {
        Write-Host "  - $($profileItem.Name): $($profileItem.SizeGB.ToString('0.000')) GB" -ForegroundColor White
    }
}
catch {
    Write-Host "FEHLER beim Schreiben der Log-Datei: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Fertig ===" -ForegroundColor Green

