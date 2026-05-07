param(
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    
    [Parameter(Mandatory=$false)]
    [int]$MinCommonLength = 20,  # Mindestlänge für gemeinsamen Teilstring
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCSV = "6.10-Aehnliche-Gruppen.csv"
)

Write-Host "=== Analyse aehnlicher Sicherheitsgruppen ===" -ForegroundColor Cyan
Write-Host "OU: $OUPath" -ForegroundColor Yellow
Write-Host "Mindestlänge gemeinsamer Teilstring: $MinCommonLength Zeichen" -ForegroundColor Yellow
Write-Host ""

Import-Module ActiveDirectory -ErrorAction Stop

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputFile = Join-Path $scriptPath $OutputCSV

# Funktion zur Berechnung der Aehnlichkeit basierend auf gemeinsamen Teilstrings
function Get-StringSimilarity {
    param(
        [string]$String1,
        [string]$String2
    )
    
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) {
        return 0
    }
    
    # Normalisiere Strings (kleinschreibung)
    $s1 = $String1.ToLower()
    $s2 = $String2.ToLower()
    
    # Prüfe auf exakte Übereinstimmung
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
    $similarity = ($commonLength / $maxLength) * 100
    return [Math]::Round($similarity, 2)
}

# Lade alle Gruppen aus der OU
Write-Host "Lade Gruppen aus OU..." -ForegroundColor Yellow
try {
    $groups = Get-ADGroup -Filter * -SearchBase $OUPath -ErrorAction Stop
    Write-Host "  Gefunden: $($groups.Count) Gruppen" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: Konnte Gruppen nicht laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($groups.Count -eq 0) {
    Write-Host "Keine Gruppen gefunden!" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Analysiere Gruppennamen auf Aehnlichkeiten..." -ForegroundColor Yellow

# Vergleiche alle Gruppen miteinander
$similarGroups = @()
$groupNames = $groups | ForEach-Object { $_.Name } | Sort-Object

$totalComparisons = ($groupNames.Count * ($groupNames.Count - 1)) / 2
$comparisonCount = 0

for ($i = 0; $i -lt $groupNames.Count; $i++) {
    for ($j = $i + 1; $j -lt $groupNames.Count; $j++) {
        $comparisonCount++
        $group1 = $groupNames[$i]
        $group2 = $groupNames[$j]
        
        # Schnelle Prüfung: Wenn Längen zu unterschiedlich, überspringe
        $lengthDiff = [Math]::Abs($group1.Length - $group2.Length)
        if ($lengthDiff -gt ($group1.Length * 0.5) -and $lengthDiff -gt ($group2.Length * 0.5)) {
            continue
        }
        
        $similarity = Get-StringSimilarity -String1 $group1 -String2 $group2
        
        # Prüfe auf gemeinsamen Teilstring
        $commonSubstring = ""
        $maxCommon = 0
        $s1 = $group1.ToLower()
        $s2 = $group2.ToLower()
        
        for ($start1 = 0; $start1 -lt $s1.Length; $start1++) {
            for ($len = $MinCommonLength; $len -le ($s1.Length - $start1); $len++) {
                $substr = $s1.Substring($start1, $len)
                if ($s2.Contains($substr) -and $len -gt $maxCommon) {
                    $maxCommon = $len
                    $commonSubstring = $substr
                }
            }
        }
        
        # Wenn gemeinsamer Teilstring gefunden oder hohe Ähnlichkeit
        if ($maxCommon -ge $MinCommonLength -or $similarity -ge 80) {
            # Prüfe auch auf gemeinsame Wörter
            $commonWords = @()
            $words1 = $group1 -split '[-\s]' | Where-Object { $_.Length -gt 2 }
            $words2 = $group2 -split '[-\s]' | Where-Object { $_.Length -gt 2 }
            
            foreach ($word in $words1) {
                if ($words2 -contains $word) {
                    $commonWords += $word
                }
            }
            
            $similarGroups += [PSCustomObject]@{
                Gruppe1 = $group1
                Gruppe2 = $group2
                Aehnlichkeit = $similarity
                GemeinsamerTeilstring = $commonSubstring
                LaengeGemeinsam = $maxCommon
                GemeinsameWoerter = ($commonWords -join ", ")
                Laenge1 = $group1.Length
                Laenge2 = $group2.Length
                Differenz = [Math]::Abs($group1.Length - $group2.Length)
            }
        }
        
        # Fortschrittsanzeige alle 500 Vergleiche
        if ($comparisonCount % 500 -eq 0) {
            $percent = [Math]::Round(($comparisonCount / $totalComparisons) * 100, 1)
            Write-Host "  Fortschritt: $percent% ($comparisonCount / $totalComparisons)" -ForegroundColor Gray
        }
    }
}

Write-Host "  Analyse abgeschlossen" -ForegroundColor Green
Write-Host ""

# Sortiere nach Ähnlichkeit (höchste zuerst)
$similarGroups = $similarGroups | Sort-Object -Property Aehnlichkeit -Descending

# Zeige Ergebnisse
Write-Host "=== Gefundene aehnliche Gruppen ===" -ForegroundColor Cyan
Write-Host "Anzahl gefundener Paare: $($similarGroups.Count)" -ForegroundColor $(if ($similarGroups.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

if ($similarGroups.Count -gt 0) {
    # Zeige Top 30
    $topGroups = $similarGroups | Select-Object -First 30
    $topGroups | Format-Table -AutoSize
    
    # Exportiere alle Ergebnisse
    $similarGroups | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host ""
    Write-Host "Alle Ergebnisse gespeichert: $outputFile" -ForegroundColor Green
    
    # Gruppiere nach sehr ähnlichen (>= 90%)
    $verySimilar = $similarGroups | Where-Object { $_.Aehnlichkeit -ge 90 }
    if ($verySimilar.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Sehr aehnliche Gruppen (>= 90%) ===" -ForegroundColor Red
        Write-Host "Anzahl: $($verySimilar.Count)" -ForegroundColor Red
        $verySimilar | Format-Table -AutoSize
    }
    
    # Gruppiere nach fast identischen (>= 95%)
    $almostIdentical = $similarGroups | Where-Object { $_.Aehnlichkeit -ge 95 }
    if ($almostIdentical.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Fast identische Gruppen (>= 95%) ===" -ForegroundColor DarkRed
        Write-Host "Anzahl: $($almostIdentical.Count)" -ForegroundColor DarkRed
        $almostIdentical | Format-Table -AutoSize
    }
} else {
    Write-Host "Keine aehnlichen Gruppen gefunden (Mindestlänge: $MinCommonLength Zeichen)" -ForegroundColor Green
}

Write-Host ""
