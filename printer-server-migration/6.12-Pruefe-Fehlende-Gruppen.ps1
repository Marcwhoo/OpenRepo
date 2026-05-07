param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$NichtGefundeneGruppenCSV = "6.9-Nicht-gefundene-Gruppen.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
)

Write-Host "=== Pruefe fehlende Gruppen gegen Drucker auf Server ===" -ForegroundColor Cyan
Write-Host "Server: $ComputerName" -ForegroundColor Yellow
Write-Host ""

Import-Module ActiveDirectory -ErrorAction Stop

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$nichtGefundeneFile = Join-Path $scriptPath $NichtGefundeneGruppenCSV

# Prüfe ob Datei existiert
if (-not (Test-Path $nichtGefundeneFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $nichtGefundeneFile" -ForegroundColor Red
    exit 1
}

# Lade nicht gefundene Gruppen
Write-Host "Lade nicht gefundene Gruppen..." -ForegroundColor Yellow
$nichtGefundene = Import-Csv -Path $nichtGefundeneFile -Delimiter ";" -Encoding UTF8
Write-Host "  Gefunden: $($nichtGefundene.Count) nicht gefundene Gruppen" -ForegroundColor Green
Write-Host ""

# Hole alle Drucker vom Server (einmalig)
Write-Host "Lade Drucker vom Server..." -ForegroundColor Yellow
try {
    $printers = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
    Write-Host "  Gefunden: $($printers.Count) Drucker" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: Konnte Drucker nicht laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Erstelle Hash-Table für schnellen Zugriff (normalisiert)
$printerHash = @{}
foreach ($printer in $printers) {
    $normalized = ($printer.Name -replace '\s+', '').ToLower()
    if (-not $printerHash.ContainsKey($normalized)) {
        $printerHash[$normalized] = @()
    }
    $printerHash[$normalized] += $printer.Name
}

Write-Host ""
Write-Host "Vergleiche nicht gefundene Gruppen mit Druckernamen..." -ForegroundColor Yellow
Write-Host ""

$matches = @()
$noMatches = @()

foreach ($nichtGefunden in $nichtGefundene) {
    $gesuchterName = $nichtGefunden.GruppenName
    
    Write-Host "Pruefe: $gesuchterName" -ForegroundColor Cyan
    
    # Normalisiere den gesuchten Namen (entferne Leerzeichen)
    $normalizedGesucht = ($gesuchterName -replace '\s+', '').ToLower()
    
    $foundMatch = $false
    
    # Schnelle Suche in Hash-Table
    if ($printerHash.ContainsKey($normalizedGesucht)) {
        $foundPrinter = $printerHash[$normalizedGesucht][0]
        Write-Host "  [EXAKT GEFUNDEN] Drucker: $foundPrinter" -ForegroundColor Green
        $matches += [PSCustomObject]@{
            GesuchterGruppenName = $gesuchterName
            GefundenerDruckerName = $foundPrinter
            MatchTyp = "Exakt (normalisiert)"
            Aehnlichkeit = 100
        }
        $foundMatch = $true
    }
    
    # Wenn nicht gefunden, suche mit Wildcard im AD
    if (-not $foundMatch) {
        # Extrahiere ersten Teil des Namens (vor dem ersten Bindestrich oder Leerzeichen)
        $firstPart = ($gesuchterName -split '[-\s]')[0]
        if ($firstPart.Length -gt 5) {
            try {
                # Suche im AD nach Gruppen, die mit diesem Teil beginnen
                $similarGroups = Get-ADGroup -Filter "Name -like '$firstPart*'" -SearchBase $OUPath -ErrorAction SilentlyContinue
                
                if ($similarGroups) {
                    # Vergleiche normalisiert
                    foreach ($group in $similarGroups) {
                        $normalizedGroup = ($group.Name -replace '\s+', '').ToLower()
                        if ($normalizedGroup -eq $normalizedGesucht) {
                            Write-Host "  [GEFUNDEN IM AD] Gruppe: $($group.Name)" -ForegroundColor Green
                            $matches += [PSCustomObject]@{
                                GesuchterGruppenName = $gesuchterName
                                GefundenerDruckerName = $group.Name
                                MatchTyp = "Gefunden im AD"
                                Aehnlichkeit = 100
                            }
                            $foundMatch = $true
                            break
                        }
                    }
                }
            } catch {
                # Ignoriere Fehler
            }
        }
    }
    
    if (-not $foundMatch) {
        Write-Host "  [NICHT GEFUNDEN] Kein passender Drucker oder Gruppe" -ForegroundColor Red
        $noMatches += [PSCustomObject]@{
            GesuchterGruppenName = $gesuchterName
            BenutzerAnzahl = $nichtGefunden.BenutzerAnzahl
        }
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Gefundene Matches: $($matches.Count)" -ForegroundColor Green
Write-Host "Nicht gefundene: $($noMatches.Count)" -ForegroundColor $(if ($noMatches.Count -gt 0) { "Red" } else { "Gray" })
Write-Host ""

if ($matches.Count -gt 0) {
    Write-Host "=== Gefundene Matches ===" -ForegroundColor Green
    $matches | Format-Table -AutoSize
    
    # Exportiere Matches
    $matchesFile = Join-Path $scriptPath "6.12-Gefundene-Matches.csv"
    $matches | Export-Csv -Path $matchesFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host "Matches gespeichert: $matchesFile" -ForegroundColor Green
}

if ($noMatches.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Nicht gefundene Gruppen ===" -ForegroundColor Red
    $noMatches | Format-Table -AutoSize
    
    # Exportiere nicht gefundene
    $noMatchesFile = Join-Path $scriptPath "6.12-Wirklich-nicht-gefunden.csv"
    $noMatches | Export-Csv -Path $noMatchesFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host "Nicht gefundene gespeichert: $noMatchesFile" -ForegroundColor Yellow
}

Write-Host ""
