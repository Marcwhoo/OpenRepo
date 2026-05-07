param(
    [Parameter(Mandatory=$false)]
    [string]$ZuordnungCSV = "6.8-Benutzer-Zuordnung.csv",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

Write-Host "=== Benutzer zu Sicherheitsgruppen hinzufuegen ===" -ForegroundColor Cyan
Write-Host ""

Import-Module ActiveDirectory -ErrorAction Stop

# Funktion zum Bereinigen von Gruppennamen (entfernt ungültige Zeichen)
function Remove-InvalidGroupCharacters {
    param([string]$GroupName)
    
    if ([string]::IsNullOrEmpty($GroupName)) {
        return $GroupName
    }
    
    # Ersetze ungültige Zeichen für AD-Gruppennamen
    # Ungültige Zeichen: / \ [ ] : ; | = , + * ? < > ( )
    $cleaned = $GroupName -replace '[\/\\\[\]:;\|=,\+\*\?<>\(\)]', '-'
    
    # Entferne mehrfache Bindestriche
    $cleaned = $cleaned -replace '-+', '-'
    
    # Entferne führende/abschließende Bindestriche
    $cleaned = $cleaned.Trim('-')
    
    # Kürze auf max. 64 Zeichen (AD-Limit)
    if ($cleaned.Length -gt 64) {
        $cleaned = $cleaned.Substring(0, 64).TrimEnd('-')
    }
    
    return $cleaned
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$zuordnungFile = Join-Path $scriptPath $ZuordnungCSV

# Prüfe ob Datei existiert
if (-not (Test-Path $zuordnungFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $zuordnungFile" -ForegroundColor Red
    exit 1
}

Write-Host "Lade Zuordnungs-Liste..." -ForegroundColor Yellow
$zuordnungen = Import-Csv -Path $zuordnungFile -Delimiter ";" -Encoding UTF8
Write-Host "  Gefunden: $($zuordnungen.Count) Zuordnungen" -ForegroundColor Green
Write-Host ""

if ($WhatIf) {
    Write-Host "HINWEIS: WhatIf-Modus aktiviert - Es werden KEINE Aenderungen vorgenommen!" -ForegroundColor Yellow
    Write-Host ""
}

# Gruppiere nach Sicherheitsgruppen
Write-Host "Gruppiere Zuordnungen nach Sicherheitsgruppen..." -ForegroundColor Yellow
$gruppenZuordnungen = @{}

foreach ($zuordnung in $zuordnungen) {
    $gruppenName = $zuordnung.NeueSicherheitsgruppe
    $benutzerName = $zuordnung.BenutzerSamAccountName
    
    if (-not $gruppenZuordnungen.ContainsKey($gruppenName)) {
        $gruppenZuordnungen[$gruppenName] = @()
    }
    
    if ($gruppenZuordnungen[$gruppenName] -notcontains $benutzerName) {
        $gruppenZuordnungen[$gruppenName] += $benutzerName
    }
}

Write-Host "  Anzahl Sicherheitsgruppen: $($gruppenZuordnungen.Keys.Count)" -ForegroundColor Green
Write-Host ""

# Verarbeite jede Sicherheitsgruppe
$addedCount = 0
$skippedCount = 0
$errorCount = 0
$notFoundGroupCount = 0
$notFoundUserCount = 0
$notFoundGroups = @()  # Liste der nicht gefundenen Gruppen
$notFoundUsers = @()    # Liste der nicht gefundenen Benutzer

$gruppenIndex = 0
foreach ($gruppenName in ($gruppenZuordnungen.Keys | Sort-Object)) {
    $gruppenIndex++
    $benutzer = $gruppenZuordnungen[$gruppenName]
    
    Write-Host "[$gruppenIndex/$($gruppenZuordnungen.Keys.Count)] $gruppenName" -ForegroundColor Cyan
    Write-Host "  Benutzer: $($benutzer.Count)" -ForegroundColor Gray
    
    # Prüfe ob Sicherheitsgruppe existiert (versuche exakt, dann bereinigt)
    $group = $null
    $actualGroupName = $gruppenName
    
    try {
        # 1. Versuche exakt mit Original-Namen
        $group = Get-ADGroup -Filter "Name -eq '$gruppenName'" -ErrorAction SilentlyContinue
        
        # 2. Falls nicht gefunden, versuche mit bereinigtem Namen
        if (-not $group) {
            $cleanedGroupName = Remove-InvalidGroupCharacters -GroupName $gruppenName
            if ($cleanedGroupName -ne $gruppenName) {
                $group = Get-ADGroup -Filter "Name -eq '$cleanedGroupName'" -ErrorAction SilentlyContinue
                if ($group) {
                    Write-Host "  [INFO] Gruppe gefunden mit bereinigtem Namen: $cleanedGroupName" -ForegroundColor Yellow
                    $actualGroupName = $cleanedGroupName
                }
            }
        }
        
        if (-not $group) {
            Write-Host "  [FEHLER] Sicherheitsgruppe nicht gefunden: $gruppenName (auch nicht mit bereinigtem Namen)" -ForegroundColor Red
            $notFoundGroupCount++
            $errorCount++
            $notFoundGroups += [PSCustomObject]@{
                GruppenName = $gruppenName
                BenutzerAnzahl = $benutzer.Count
            }
            continue
        }
    } catch {
        Write-Host "  [FEHLER] Konnte Sicherheitsgruppe nicht prüfen: $($_.Exception.Message)" -ForegroundColor Red
        $notFoundGroupCount++
        $errorCount++
        $notFoundGroups += [PSCustomObject]@{
            GruppenName = $gruppenName
            BenutzerAnzahl = $benutzer.Count
            Fehler = $_.Exception.Message
        }
        continue
    }
    
    # Hole aktuelle Mitglieder der Gruppe
    $currentMembers = @()
    try {
        $currentMembers = (Get-ADGroupMember -Identity $group -ErrorAction Stop | ForEach-Object { $_.SamAccountName })
    } catch {
        Write-Host "  [WARNUNG] Konnte aktuelle Mitglieder nicht laden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Verarbeite jeden Benutzer
    foreach ($benutzerSamAccountName in $benutzer) {
        try {
            # Prüfe ob Benutzer existiert
            $user = Get-ADUser -Filter "SamAccountName -eq '$benutzerSamAccountName'" -ErrorAction SilentlyContinue
            if (-not $user) {
                Write-Host "    [FEHLER] Benutzer nicht gefunden: $benutzerSamAccountName" -ForegroundColor Red
                $notFoundUserCount++
                $errorCount++
                $notFoundUsers += [PSCustomObject]@{
                    GruppenName = $gruppenName
                    BenutzerSamAccountName = $benutzerSamAccountName
                }
                continue
            }
            
            # Prüfe ob Benutzer bereits in Gruppe ist
            $isMember = $currentMembers -contains $benutzerSamAccountName
            
            if ($isMember) {
                if ($Force) {
                    Write-Host "    [INFO] Bereits Mitglied, wird uebersprungen: $benutzerSamAccountName" -ForegroundColor Gray
                    $skippedCount++
                } else {
                    Write-Host "    [INFO] Bereits Mitglied: $benutzerSamAccountName" -ForegroundColor Gray
                    $skippedCount++
                }
            } else {
                if ($WhatIf) {
                    Write-Host "    [WHATIF] Wuerde hinzufuegen: $benutzerSamAccountName" -ForegroundColor Yellow
                    $addedCount++
                } else {
                    # Füge Benutzer zur Gruppe hinzu
                    Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
                    Write-Host "    [OK] Hinzugefuegt: $benutzerSamAccountName" -ForegroundColor Green
                    $addedCount++
                    
                    # Aktualisiere lokale Liste der Mitglieder
                    $currentMembers += $benutzerSamAccountName
                }
            }
        } catch {
            Write-Host "    [FEHLER] Konnte Benutzer nicht hinzufuegen: $benutzerSamAccountName - $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Benutzer hinzugefuegt: $addedCount" -ForegroundColor Green
Write-Host "Bereits Mitglied: $skippedCount" -ForegroundColor Gray
Write-Host "Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "  - Gruppen nicht gefunden: $notFoundGroupCount" -ForegroundColor $(if ($notFoundGroupCount -gt 0) { "Red" } else { "Gray" })
Write-Host "  - Benutzer nicht gefunden: $notFoundUserCount" -ForegroundColor $(if ($notFoundUserCount -gt 0) { "Red" } else { "Gray" })
Write-Host ""

# Zeige nicht gefundene Gruppen
if ($notFoundGroups.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Nicht gefundene Sicherheitsgruppen ===" -ForegroundColor Red
    $notFoundGroups | Format-Table -AutoSize
    
    # Exportiere nicht gefundene Gruppen in CSV
    $notFoundGroupsFile = Join-Path $scriptPath "6.9-Nicht-gefundene-Gruppen.csv"
    $notFoundGroups | Export-Csv -Path $notFoundGroupsFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host "Liste der nicht gefundenen Gruppen gespeichert: $notFoundGroupsFile" -ForegroundColor Yellow
}

# Zeige nicht gefundene Benutzer
if ($notFoundUsers.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Nicht gefundene Benutzer ===" -ForegroundColor Red
    $notFoundUsers | Format-Table -AutoSize
    
    # Exportiere nicht gefundene Benutzer in CSV
    $notFoundUsersFile = Join-Path $scriptPath "6.9-Nicht-gefundene-Benutzer.csv"
    $notFoundUsers | Export-Csv -Path $notFoundUsersFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host "Liste der nicht gefundenen Benutzer gespeichert: $notFoundUsersFile" -ForegroundColor Yellow
}

Write-Host ""

if ($WhatIf) {
    Write-Host "HINWEIS: WhatIf-Modus - Keine Aenderungen wurden vorgenommen!" -ForegroundColor Yellow
    Write-Host "Fuehren Sie das Script ohne -WhatIf aus, um die Aenderungen durchzufuehren." -ForegroundColor Yellow
} else {
    Write-Host "Alle Aenderungen wurden durchgefuehrt." -ForegroundColor Green
}
