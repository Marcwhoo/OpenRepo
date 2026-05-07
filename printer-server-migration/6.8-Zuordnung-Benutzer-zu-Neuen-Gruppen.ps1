param(
    [Parameter(Mandatory=$false)]
    [string]$SecurityGroupsCSV = "1.3-Sicherheitsgruppen-Bestandsaufnahme.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$ZuordnungCSV = "3.2-Zuordnung-Drucker-Namen.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCSV = "6.8-Benutzer-Zuordnung.csv",
    
    [Parameter(Mandatory=$false)]
    [switch]$Execute = $false
)

Write-Host "=== Zuordnung Benutzer zu neuen Sicherheitsgruppen ===" -ForegroundColor Cyan
Write-Host ""

Import-Module ActiveDirectory -ErrorAction Stop

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$securityGroupsFile = Join-Path $scriptPath $SecurityGroupsCSV
$zuordnungFile = Join-Path $scriptPath $ZuordnungCSV
$outputFile = Join-Path $scriptPath $OutputCSV

# Prüfe ob Dateien existieren
if (-not (Test-Path $securityGroupsFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $securityGroupsFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $zuordnungFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $zuordnungFile" -ForegroundColor Red
    exit 1
}

Write-Host "Lade CSV-Dateien..." -ForegroundColor Yellow
$securityGroups = Import-Csv -Path $securityGroupsFile -Delimiter ";" -Encoding UTF8
$zuordnung = Import-Csv -Path $zuordnungFile -Delimiter ";" -Encoding UTF8

Write-Host "  Sicherheitsgruppen: $($securityGroups.Count) Eintraege" -ForegroundColor Green
Write-Host "  Zuordnung: $($zuordnung.Count) Eintraege" -ForegroundColor Green
Write-Host ""

# Erstelle Mapping: Alter Druckername -> Neuer Druckername
Write-Host "Erstelle Zuordnungs-Mapping..." -ForegroundColor Yellow
$mapping = @{}
foreach ($entry in $zuordnung) {
    $oldName = $entry.OldPrinterName
    $newName = $entry.NewPrinterName
    if ($oldName -and $newName) {
        if (-not $mapping.ContainsKey($oldName)) {
            $mapping[$oldName] = @()
        }
        $mapping[$oldName] += $newName
    }
}

Write-Host "  Mapping-Eintraege: $($mapping.Count)" -ForegroundColor Green
Write-Host ""

# Sammle alle Benutzer-Zuordnungen
Write-Host "Analysiere Benutzer-Zuordnungen..." -ForegroundColor Yellow
$userAssignments = @{}
$processedGroups = @{}

foreach ($sgEntry in $securityGroups) {
    $oldPrinterName = $sgEntry.PrinterName
    $oldSecurityGroup = $sgEntry.SecurityGroup
    $members = $sgEntry.Members
    
    # Prüfe ob dieser Drucker in der Zuordnung vorhanden ist
    if ($mapping.ContainsKey($oldPrinterName)) {
        $newPrinterNames = $mapping[$oldPrinterName]
        
        # Extrahiere Benutzer aus Members-String
        if ($members) {
            # Parse Members-String: "Name, Vorname (samaccountname); Name2, Vorname2 (samaccountname2)"
            $memberList = $members -split ';' | ForEach-Object { $_.Trim() }
            
            foreach ($member in $memberList) {
                # Extrahiere SamAccountName aus Format: "Name, Vorname (samaccountname)"
                if ($member -match '\(([^)]+)\)$') {
                    $samAccountName = $matches[1]
                    
                    # Für jeden neuen Drucker (neue Sicherheitsgruppe)
                    foreach ($newPrinterName in $newPrinterNames) {
                        # Neue Sicherheitsgruppe hat den gleichen Namen wie der neue Drucker
                        $newGroupName = $newPrinterName
                        
                        if (-not $userAssignments.ContainsKey($newGroupName)) {
                            $userAssignments[$newGroupName] = @()
                        }
                        
                        # Füge Benutzer hinzu, wenn noch nicht vorhanden
                        if ($userAssignments[$newGroupName] -notcontains $samAccountName) {
                            $userAssignments[$newGroupName] += $samAccountName
                        }
                    }
                }
            }
        }
    }
}

# Erstelle Ausgabe-Liste
Write-Host "Erstelle Zuordnungs-Liste..." -ForegroundColor Yellow
$assignments = @()

foreach ($newGroupName in $userAssignments.Keys) {
    $users = $userAssignments[$newGroupName]
    
    foreach ($user in $users) {
        $assignments += [PSCustomObject]@{
            NeueSicherheitsgruppe = $newGroupName
            BenutzerSamAccountName = $user
            Status = "Zuordnen"
        }
    }
}

# Exportiere Zuordnung
$assignments | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
Write-Host "Zuordnungs-Liste erstellt: $outputFile" -ForegroundColor Green
Write-Host "  Anzahl Zuordnungen: $($assignments.Count)" -ForegroundColor Green
Write-Host "  Anzahl neue Sicherheitsgruppen: $($userAssignments.Keys.Count)" -ForegroundColor Green
Write-Host ""

# Zeige Zusammenfassung
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
$summary = $userAssignments.Keys | ForEach-Object {
    [PSCustomObject]@{
        Sicherheitsgruppe = $_
        BenutzerAnzahl = $userAssignments[$_].Count
    }
} | Sort-Object Sicherheitsgruppe

$summary | Format-Table -AutoSize

# Wenn Execute aktiviert, füge Benutzer zu Gruppen hinzu
if ($Execute) {
    Write-Host ""
    Write-Host "=== Fuege Benutzer zu neuen Sicherheitsgruppen hinzu ===" -ForegroundColor Cyan
    
    $addedCount = 0
    $errorCount = 0
    $skippedCount = 0
    
    foreach ($newGroupName in $userAssignments.Keys) {
        Write-Host "Gruppe: $newGroupName" -ForegroundColor Yellow
        
        # Prüfe ob Gruppe existiert
        try {
            $group = Get-ADGroup -Filter "Name -eq '$newGroupName'" -ErrorAction Stop
            if (-not $group) {
                Write-Host "  [FEHLER] Sicherheitsgruppe nicht gefunden: $newGroupName" -ForegroundColor Red
                $errorCount++
                continue
            }
        } catch {
            Write-Host "  [FEHLER] Konnte Sicherheitsgruppe nicht prüfen: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
            continue
        }
        
        $users = $userAssignments[$newGroupName]
        Write-Host "  Benutzer: $($users.Count)" -ForegroundColor Cyan
        
        foreach ($userSamAccountName in $users) {
            try {
                # Prüfe ob Benutzer existiert
                $user = Get-ADUser -Filter "SamAccountName -eq '$userSamAccountName'" -ErrorAction SilentlyContinue
                if (-not $user) {
                    Write-Host "    [ÜBERSPRUNGEN] Benutzer nicht gefunden: $userSamAccountName" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                }
                
                # Prüfe ob Benutzer bereits in Gruppe ist
                $isMember = (Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $userSamAccountName })
                
                if ($isMember) {
                    Write-Host "    [INFO] Bereits Mitglied: $userSamAccountName" -ForegroundColor Gray
                    $skippedCount++
                } else {
                    # Füge Benutzer zur Gruppe hinzu
                    Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
                    Write-Host "    [OK] Hinzugefuegt: $userSamAccountName" -ForegroundColor Green
                    $addedCount++
                }
            } catch {
                Write-Host "    [FEHLER] Konnte Benutzer nicht hinzufuegen: $userSamAccountName - $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
            }
        }
    }
    
    Write-Host ""
    Write-Host "=== Ergebnis ===" -ForegroundColor Cyan
    Write-Host "Benutzer hinzugefuegt: $addedCount" -ForegroundColor Green
    Write-Host "Bereits Mitglied: $skippedCount" -ForegroundColor Gray
    Write-Host "Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
} else {
    Write-Host ""
    Write-Host "HINWEIS: Benutzer wurden noch NICHT zu Gruppen hinzugefuegt." -ForegroundColor Yellow
    Write-Host "Verwenden Sie -Execute, um die Benutzer tatsaechlich hinzuzufuegen." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Beispiel:" -ForegroundColor Cyan
    Write-Host "  .\6.8-Zuordnung-Benutzer-zu-Neuen-Gruppen.ps1 -Execute" -ForegroundColor White
}
