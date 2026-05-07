param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    
    [Parameter(Mandatory=$false)]
    [string]$NichtGefundeneGruppenCSV = "6.9-Nicht-gefundene-Gruppen.csv"
)

Write-Host "=== Erstelle fehlende Sicherheitsgruppen ===" -ForegroundColor Cyan
Write-Host "Server: $ComputerName" -ForegroundColor Yellow
Write-Host "OU: $OUPath" -ForegroundColor Yellow
Write-Host ""

# Prüfe ob ActiveDirectory Module verfügbar ist
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "FEHLER: ActiveDirectory Module nicht gefunden." -ForegroundColor Red
    Write-Host "Bitte installieren Sie es mit: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit 1
}

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

# Prüfe ob OU existiert
try {
    $null = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
    Write-Host "OU gefunden: $OUPath" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: OU nicht gefunden: $OUPath" -ForegroundColor Red
    Write-Host "Bitte prüfen Sie den OU-Pfad." -ForegroundColor Yellow
    exit 1
}

# Lade fehlende Gruppen aus CSV
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$nichtGefundeneFile = Join-Path $scriptPath $NichtGefundeneGruppenCSV

if (-not (Test-Path $nichtGefundeneFile)) {
    Write-Host "FEHLER: Datei nicht gefunden: $nichtGefundeneFile" -ForegroundColor Red
    exit 1
}

Write-Host "Lade fehlende Gruppen aus CSV..." -ForegroundColor Yellow
$fehlendeGruppen = Import-Csv -Path $nichtGefundeneFile -Delimiter ";" -Encoding UTF8
Write-Host "  Gefunden: $($fehlendeGruppen.Count) fehlende Gruppen" -ForegroundColor Green
Write-Host ""

# Lade alle vorhandenen Gruppen aus OU einmalig (für schnelle Prüfung)
Write-Host "Lade vorhandene Gruppen aus OU..." -ForegroundColor Yellow
$existingGroupsHash = @{}
try {
    $allExistingGroups = Get-ADGroup -Filter * -SearchBase $OUPath -ErrorAction Stop
    foreach ($existingGroup in $allExistingGroups) {
        $existingGroupsHash[$existingGroup.Name] = $existingGroup
    }
    Write-Host "  Gefunden: $($allExistingGroups.Count) vorhandene Gruppen" -ForegroundColor Green
} catch {
    Write-Host "  [WARNUNG] Konnte vorhandene Gruppen nicht laden: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Lade alle Drucker einmalig (für schnelle Prüfung)
Write-Host "Lade Drucker vom Server..." -ForegroundColor Yellow
$printersHash = @{}  # Exakte Namen
$printersHashNormalized = @{}  # Normalisierte Namen (ohne Leerzeichen, lowercase)
try {
    $allPrinters = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
    foreach ($printer in $allPrinters) {
        $printerName = $printer.Name
        $printersHash[$printerName] = $printer
        
        # Erstelle auch normalisierten Eintrag (ohne Leerzeichen, lowercase)
        $normalized = ($printerName -replace '\s+', '').ToLower()
        if (-not $printersHashNormalized.ContainsKey($normalized)) {
            $printersHashNormalized[$normalized] = @()
        }
        $printersHashNormalized[$normalized] += $printerName
    }
    Write-Host "  Gefunden: $($allPrinters.Count) Drucker" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Konnte Drucker nicht laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

$createdCount = 0
$existingCount = 0
$errorCount = 0
$assignedCount = 0
$notFoundAsPrinterCount = 0

$gruppenIndex = 0
foreach ($fehlendeGruppe in $fehlendeGruppen) {
    $gruppenIndex++
    $originalGroupName = $fehlendeGruppe.GruppenName
    $groupName = Remove-InvalidGroupCharacters -GroupName $originalGroupName
    
    Write-Host "[$gruppenIndex/$($fehlendeGruppen.Count)] $originalGroupName" -ForegroundColor Cyan
    
    if ($groupName -ne $originalGroupName) {
        Write-Host "  [INFO] Gruppenname bereinigt: '$originalGroupName' -> '$groupName'" -ForegroundColor Yellow
    }
    
    # Prüfe ob Drucker existiert (exakt, bereinigt, oder normalisiert)
    $printerFound = $false
    $printerName = $null
    
    # 1. Versuche exakt mit Original-Namen
    if ($printersHash.ContainsKey($originalGroupName)) {
        $printerFound = $true
        $printerName = $originalGroupName
    }
    
    # 2. Versuche exakt mit bereinigtem Namen
    if (-not $printerFound -and $printersHash.ContainsKey($groupName)) {
        $printerFound = $true
        $printerName = $groupName
    }
    
    # 3. Versuche normalisiert (ohne Leerzeichen, lowercase)
    if (-not $printerFound) {
        $normalizedGesucht = ($originalGroupName -replace '\s+', '').ToLower()
        if ($printersHashNormalized.ContainsKey($normalizedGesucht)) {
            $printerFound = $true
            $printerName = $printersHashNormalized[$normalizedGesucht][0]
            Write-Host "  [INFO] Drucker gefunden (normalisiert): '$printerName'" -ForegroundColor Yellow
        }
    }
    
    # 4. Versuche Teilstring-Suche (für Variationen wie "raße" vs "str.")
    if (-not $printerFound) {
        # Extrahiere wichtige Teile: Modell (z.B. J5340DW, MFC-L3770CDW) und Standort (z.B. HE-Haus-2-EG)
        # Suche nach Modell-Mustern (BRO-MFC-XXX, KON-XXX, KYO-XXX)
        $modelMatch = $originalGroupName -match '-(BRO|KON|KYO|CAN)-([A-Z0-9-]+)-'
        if ($modelMatch) {
            $modelPart = $matches[0]  # z.B. "-BRO-MFC-J5340DW-"
            
            # Extrahiere Standort-Teile (nach dem Modell)
            $afterModel = $originalGroupName -split $modelPart, 2 | Select-Object -Last 1
            $locationParts = $afterModel -split '-' | Where-Object { $_.Length -gt 2 } | Select-Object -First 3
            
            # Suche nach Druckern mit diesem Modell und ähnlichem Standort
            $matchingPrinters = $allPrinters | Where-Object { 
                $printerNameCheck = $_.Name
                $printerNormalized = ($printerNameCheck -replace '\s+', '').ToLower()
                $modelPartLower = $modelPart.ToLower()
                
                # Muss Modell enthalten
                if ($printerNormalized -like "*$modelPartLower*") {
                    # Prüfe ob Standort-Teile übereinstimmen
                    $locationMatchCount = 0
                    foreach ($locPart in $locationParts) {
                        if ($printerNormalized -like "*$($locPart.ToLower())*") {
                            $locationMatchCount++
                        }
                    }
                    # Mindestens 2 Standort-Teile müssen übereinstimmen
                    return $locationMatchCount -ge 2
                }
                return $false
            }
            
            if ($matchingPrinters.Count -eq 1) {
                $printerFound = $true
                $printerName = $matchingPrinters[0].Name
                Write-Host "  [INFO] Drucker gefunden (Teilstring-Suche): '$printerName'" -ForegroundColor Yellow
            } elseif ($matchingPrinters.Count -gt 1) {
                # Mehrere Treffer - wähle den mit der höchsten Übereinstimmung
                $normalizedGesucht = ($originalGroupName -replace '\s+', '').ToLower()
                $bestMatch = $matchingPrinters | ForEach-Object {
                    $printerNormalized = ($_.Name -replace '\s+', '').ToLower()
                    # Zähle übereinstimmende Zeichen am Anfang/Ende
                    $similarity = 0
                    $minLen = [Math]::Min($normalizedGesucht.Length, $printerNormalized.Length)
                    for ($i = 0; $i -lt $minLen; $i++) {
                        if ($normalizedGesucht[$i] -eq $printerNormalized[$i]) {
                            $similarity++
                        } else {
                            break
                        }
                    }
                    [PSCustomObject]@{ Name = $_.Name; Similarity = $similarity }
                } | Sort-Object -Property Similarity -Descending | Select-Object -First 1
                
                if ($bestMatch -and $bestMatch.Similarity -gt 20) {
                    $printerFound = $true
                    $printerName = $bestMatch.Name
                    Write-Host "  [INFO] Drucker gefunden (Teilstring-Suche, mehrere Treffer): '$printerName'" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # Prüfe ob Gruppe bereits existiert (mit bereinigtem Namen)
    if ($existingGroupsHash.ContainsKey($groupName)) {
        Write-Host "  [INFO] Gruppe existiert bereits in AD" -ForegroundColor Green
        $existingCount++
        $group = $existingGroupsHash[$groupName]
    } else {
        if ($printerFound) {
            Write-Host "  [INFO] Drucker gefunden, erstelle Gruppe..." -ForegroundColor Yellow
            try {
                $group = New-ADGroup -Name $groupName -GroupScope DomainLocal -Path $OUPath -ErrorAction Stop
                $existingGroupsHash[$groupName] = $group
                Write-Host "  [OK] Gruppe erstellt: $groupName" -ForegroundColor Green
                $createdCount++
            } catch {
                $errorMsg = if ($_.Exception.Message) { $_.Exception.Message } else { $_.Exception.ToString() }
                Write-Host "  [FEHLER] Konnte Gruppe nicht erstellen: $errorMsg" -ForegroundColor Red
                $errorCount++
                continue
            }
        } else {
            Write-Host "  [WARNUNG] Drucker nicht gefunden auf Server" -ForegroundColor Yellow
            $notFoundAsPrinterCount++
            continue
        }
    }
    
    # Weise Gruppe dem Drucker zu (nur wenn Drucker existiert)
    # Verwende den bereits gefundenen Druckernamen
    if ($printerName) {
        $printerNameToUse = $printerName
        try {
            $printerName = $printerNameToUse
            $printerWmi = Get-WmiObject -ComputerName $ComputerName -Class Win32_Printer -Filter "Name='$($printerName -replace "'", "''")'" -ErrorAction Stop
            
            if (-not $printerWmi) {
                Write-Host "  [FEHLER] Drucker nicht gefunden via WMI" -ForegroundColor Red
                $errorCount++
                continue
            }
            
            # Hole Security Descriptor
            $sdResult = $printerWmi.GetSecurityDescriptor()
            if ($sdResult.ReturnValue -ne 0) {
                Write-Host "  [FEHLER] Konnte Berechtigungen nicht abrufen (ReturnValue: $($sdResult.ReturnValue))" -ForegroundColor Red
                $errorCount++
                continue
            }
            
            $descriptor = $sdResult.Descriptor
            $groupSid = $group.SID.Value
            
            # Erstelle Trustee-Objekt
            $trustee = ([WMIClass]"Win32_Trustee").CreateInstance()
            $trustee.SIDString = $groupSid
            $trustee.Name = $groupName
            $trustee.Domain = ""
            
            # Definiere die drei ACEs
            $requiredAces = @(
                @{ AccessMask = 0x00020000; AceFlags = 10 },  # Print
                @{ AccessMask = 0x000F0030; AceFlags = 9 },   # Full Control
                @{ AccessMask = 0x00020008; AceFlags = 0 }    # Print + Manage Documents
            )
            
            # Entferne ALLE bestehenden ACEs der Gruppe und sammle andere ACEs
            $existingAces = @()
            $newDacl = New-Object System.Collections.ArrayList
            $groupAceFound = $false
            
            foreach ($existingAce in $descriptor.DACL) {
                if ($existingAce.Trustee.SIDString -eq $groupSid) {
                    $existingAces += @{
                        AccessMask = $existingAce.AccessMask
                        AceFlags = $existingAce.AceFlags
                    }
                    $groupAceFound = $true
                } else {
                    [void]$newDacl.Add($existingAce)
                }
            }
            
            # Prüfe ob alle drei ACEs vorhanden sind
            $allAcesPresent = $false
            if ($existingAces.Count -eq 3) {
                $foundCount = 0
                foreach ($requiredAce in $requiredAces) {
                    foreach ($existingAce in $existingAces) {
                        if ($existingAce.AccessMask -eq $requiredAce.AccessMask -and 
                            $existingAce.AceFlags -eq $requiredAce.AceFlags) {
                            $foundCount++
                            break
                        }
                    }
                }
                if ($foundCount -eq 3) {
                    $allAcesPresent = $true
                }
            }
            
            if (-not $allAcesPresent) {
                # Erstelle die drei ACEs
                foreach ($requiredAce in $requiredAces) {
                    $ace = ([WMIClass]"Win32_ACE").CreateInstance()
                    $ace.AccessMask = $requiredAce.AccessMask
                    $ace.AceType = 0
                    $ace.AceFlags = $requiredAce.AceFlags
                    $ace.Trustee = $trustee
                    [void]$newDacl.Add($ace)
                }
                
                $descriptor.DACL = $newDacl.ToArray()
                $setResult = $printerWmi.SetSecurityDescriptor($descriptor)
                
                if ($setResult.ReturnValue -eq 0) {
                    if ($groupAceFound) {
                        Write-Host "  [OK] Berechtigungen aktualisiert" -ForegroundColor Green
                    } else {
                        Write-Host "  [OK] Gruppe dem Drucker zugewiesen" -ForegroundColor Green
                    }
                    $assignedCount++
                } else {
                    Write-Host "  [FEHLER] Konnte Gruppe nicht zuweisen (ReturnValue: $($setResult.ReturnValue))" -ForegroundColor Red
                    $errorCount++
                }
            } else {
                Write-Host "  [INFO] Gruppe bereits korrekt zugewiesen" -ForegroundColor Gray
                $assignedCount++
            }
            
        } catch {
            $errorMsg = if ($_.Exception.Message) { $_.Exception.Message } else { $_.Exception.ToString() }
            Write-Host "  [FEHLER] Beim Zuweisen: $errorMsg" -ForegroundColor Red
            $errorCount++
        }
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Neue Gruppen erstellt: $createdCount" -ForegroundColor Green
Write-Host "Bereits vorhandene Gruppen: $existingCount" -ForegroundColor Gray
Write-Host "Gruppen zugewiesen: $assignedCount" -ForegroundColor Green
Write-Host "Drucker nicht gefunden: $notFoundAsPrinterCount" -ForegroundColor Yellow
Write-Host "Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Gesamt fehlende Gruppen: $($fehlendeGruppen.Count)" -ForegroundColor White
