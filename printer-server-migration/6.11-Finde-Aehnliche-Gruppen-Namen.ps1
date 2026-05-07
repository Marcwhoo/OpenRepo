param(
    [Parameter(Mandatory=$false)]
    [string]$NichtGefundeneGruppenCSV = "6.9-Nicht-gefundene-Gruppen.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    
    [Parameter(Mandatory=$false)]
    [int]$SimilarityThreshold = 80,  # Prozent (0-100)
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCSV = "6.11-Aehnliche-Gruppen-Gefunden.csv"
)

Write-Host "=== Suche aehnliche Gruppen-Namen fuer nicht gefundene Gruppen ===" -ForegroundColor Cyan
Write-Host ""

Import-Module ActiveDirectory -ErrorAction Stop

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$nichtGefundeneFile = Join-Path $scriptPath $NichtGefundeneGruppenCSV
$outputFile = Join-Path $scriptPath $OutputCSV

# Prüfe ob Datei existiert
if (-not (Test-Path $nichtGefundeneFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $nichtGefundeneFile" -ForegroundColor Red
    Write-Host "Fuehren Sie zuerst 6.9-Hinzufuegen-Benutzer-zu-Gruppen.ps1 aus, um die Liste zu erstellen." -ForegroundColor Yellow
    exit 1
}

# Funktion zur Berechnung der Aehnlichkeit
function Get-StringSimilarity {
    param(
        [string]$String1,
        [string]$String2
    )
    
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) {
        return 0
    }
    
    # Normalisiere Strings (kleinschreibung, Leerzeichen entfernen)
    $s1 = ($String1.ToLower() -replace '\s+', '').Trim()
    $s2 = ($String2.ToLower() -replace '\s+', '').Trim()
    
    # Prüfe auf exakte Übereinstimmung (nach Normalisierung)
    if ($s1 -eq $s2) {
        return 100
    }
    
    # Finde längsten gemeinsamen Teilstring
    $maxLength = [Math]::Max($s1.Length, $s2.Length)
    $commonLength = 0
    
    # Prüfe alle möglichen Teilstrings
    for ($i = 0; $i -lt $s1.Length; $i++) {
        for ($j = 0; $j -lt $s2.Length; $j++) {
            $k = 0
            while (($i + $k) -lt $s1.Length -and ($j + $k) -lt $s2.Length -and $s1[$i + $k] -eq $s2[$j + $k]) {
                $k++
            }
            if ($k -gt $commonLength) {
                $commonLength = $k
            }
        }
    }
    
    # Berechne Ähnlichkeit
    if ($maxLength -eq 0) {
        return 0
    }
    $similarity = ($commonLength / $maxLength) * 100
    return [Math]::Round($similarity, 2)
}

# Lade nicht gefundene Gruppen
Write-Host "Lade nicht gefundene Gruppen..." -ForegroundColor Yellow
$nichtGefundene = Import-Csv -Path $nichtGefundeneFile -Delimiter ";" -Encoding UTF8
Write-Host "  Gefunden: $($nichtGefundene.Count) nicht gefundene Gruppen" -ForegroundColor Green
Write-Host ""

# Lade alle Gruppen aus der OU
Write-Host "Lade alle Gruppen aus OU: $OUPath" -ForegroundColor Yellow
try {
    $allGroups = Get-ADGroup -Filter * -SearchBase $OUPath -ErrorAction Stop
    Write-Host "  Gefunden: $($allGroups.Count) Gruppen in OU" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: Konnte Gruppen nicht laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($allGroups.Count -eq 0) {
    Write-Host "Keine Gruppen in OU gefunden!" -ForegroundColor Yellow
    exit 0
}

# Erstelle Liste aller Gruppennamen
$allGroupNames = $allGroups | ForEach-Object { $_.Name }

Write-Host ""
Write-Host "Suche aehnliche Gruppen-Namen..." -ForegroundColor Yellow

$foundSimilar = @()

foreach ($nichtGefunden in $nichtGefundene) {
    $gesuchterName = $nichtGefunden.GruppenName
    
    Write-Host "Suche fuer: $gesuchterName" -ForegroundColor Cyan
    
    $bestMatches = @()
    
    # Vergleiche mit allen Gruppen
    foreach ($existingGroupName in $allGroupNames) {
        $similarity = Get-StringSimilarity -String1 $gesuchterName -String2 $existingGroupName
        
        if ($similarity -ge $SimilarityThreshold) {
            # Prüfe auch auf gemeinsame Wörter
            $words1 = $gesuchterName -split '[-\s]' | Where-Object { $_.Length -gt 2 }
            $words2 = $existingGroupName -split '[-\s]' | Where-Object { $_.Length -gt 2 }
            $commonWords = @()
            
            foreach ($word in $words1) {
                if ($words2 -contains $word) {
                    $commonWords += $word
                }
            }
            
            $bestMatches += [PSCustomObject]@{
                GesuchterName = $gesuchterName
                GefundenerName = $existingGroupName
                Aehnlichkeit = $similarity
                GemeinsameWoerter = ($commonWords -join ", ")
                LaengeGesucht = $gesuchterName.Length
                LaengeGefunden = $existingGroupName.Length
                Differenz = [Math]::Abs($gesuchterName.Length - $existingGroupName.Length)
            }
        }
    }
    
    # Sortiere nach Ähnlichkeit
    $bestMatches = $bestMatches | Sort-Object -Property Aehnlichkeit -Descending
    
    if ($bestMatches.Count -gt 0) {
        Write-Host "  [GEFUNDEN] $($bestMatches.Count) aehnliche Gruppen:" -ForegroundColor Green
        foreach ($match in $bestMatches | Select-Object -First 5) {
            Write-Host "    - $($match.GefundenerName) ($($match.Aehnlichkeit)%)" -ForegroundColor Yellow
        }
        $foundSimilar += $bestMatches
    } else {
        Write-Host "  [NICHT GEFUNDEN] Keine aehnlichen Gruppen gefunden" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan

if ($foundSimilar.Count -gt 0) {
    # Gruppiere nach gesuchtem Namen
    $grouped = $foundSimilar | Group-Object -Property GesuchterName
    
    Write-Host "Fuer $($grouped.Count) nicht gefundene Gruppen wurden aehnliche Namen gefunden" -ForegroundColor Green
    Write-Host "Gesamt gefundene aehnliche Gruppen: $($foundSimilar.Count)" -ForegroundColor Green
    Write-Host ""
    
    # Zeige Top 20
    $topMatches = $foundSimilar | Sort-Object -Property Aehnlichkeit -Descending | Select-Object -First 20
    Write-Host "=== Top 20 aehnlichste Treffer ===" -ForegroundColor Cyan
    $topMatches | Format-Table -AutoSize
    
    # Exportiere alle Ergebnisse
    $foundSimilar | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host ""
    Write-Host "Alle Ergebnisse gespeichert: $outputFile" -ForegroundColor Green
    
    # Zeige sehr ähnliche (>= 95%)
    $verySimilar = $foundSimilar | Where-Object { $_.Aehnlichkeit -ge 95 } | Sort-Object -Property Aehnlichkeit -Descending
    if ($verySimilar.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Sehr aehnliche Gruppen (>= 95%) - Moegliche Treffer ===" -ForegroundColor Green
        $verySimilar | Format-Table -AutoSize
    }
} else {
    Write-Host "Keine aehnlichen Gruppen gefunden (Schwelle: $SimilarityThreshold%)" -ForegroundColor Yellow
}

Write-Host ""
