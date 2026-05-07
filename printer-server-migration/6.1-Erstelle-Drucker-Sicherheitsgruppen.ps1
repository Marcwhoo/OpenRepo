param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
)

Write-Host "=== Erstelle Sicherheitsgruppen für Drucker ===" -ForegroundColor Cyan
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

# Prüfe ob OU existiert
try {
    $null = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
    Write-Host "OU gefunden: $OUPath" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: OU nicht gefunden: $OUPath" -ForegroundColor Red
    Write-Host "Bitte prüfen Sie den OU-Pfad." -ForegroundColor Yellow
    exit 1
}

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
    Write-Host "  Pruefe jeden Drucker einzeln..." -ForegroundColor Yellow
}
Write-Host ""

# Hole alle Drucker
Write-Host "Lade Drucker..." -ForegroundColor Yellow
$printers = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
Write-Host "Gefunden: $($printers.Count) Drucker" -ForegroundColor Green
Write-Host ""

$createdCount = 0
$existingCount = 0
$errorCount = 0
$assignedCount = 0

$printerIndex = 0
foreach ($printer in $printers) {
    $printerIndex++
    $printerName = $printer.Name
    $groupName = $printerName
    
    Write-Host "[$printerIndex/$($printers.Count)] $printerName" -ForegroundColor Cyan
    
    # Erstelle Sicherheitsgruppe
    try {
        # Schnelle Hash-Table-Prüfung
        $existingGroup = $null
        if ($existingGroupsHash.ContainsKey($groupName)) {
            $existingGroup = $existingGroupsHash[$groupName]
        }
        
        if ($existingGroup) {
            Write-Host "  Gruppe bereits vorhanden: $groupName" -ForegroundColor Yellow
            $existingCount++
            $group = $existingGroup
        } else {
            # Erstelle neue Gruppe
            $group = New-ADGroup -Name $groupName -GroupScope DomainLocal -Path $OUPath -ErrorAction Stop
            # Füge zur Hash-Table hinzu für zukünftige Prüfungen
            $existingGroupsHash[$groupName] = $group
            Write-Host "  [OK] Gruppe erstellt: $groupName" -ForegroundColor Green
            $createdCount++
        }
        
        # Weise Gruppe dem Drucker zu
        try {
            $printerWmi = Get-WmiObject -ComputerName $ComputerName -Class Win32_Printer -Filter "Name='$($printerName -replace "'", "''")'" -ErrorAction Stop
            
            if (-not $printerWmi) {
                Write-Host "  [FEHLER] Drucker nicht gefunden" -ForegroundColor Red
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
            
            # Erstelle Trustee-Objekt (einmal für alle ACEs)
            $trustee = ([WMIClass]"Win32_Trustee").CreateInstance()
            $trustee.SIDString = $groupSid
            $trustee.Name = $groupName
            $trustee.Domain = ""
            
            # Definiere die drei ACEs genau wie beim manuell konfigurierten Drucker
            # Diese Werte ermöglichen "Drucken" und "Dokumente verwalten"
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
                    # Entferne diese ACE (nicht zu newDacl hinzufügen)
                } else {
                    [void]$newDacl.Add($existingAce)
                }
            }
            
            # Prüfe ob alle drei ACEs vorhanden sind (exakt mit AccessMask und AceFlags)
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
                # Erstelle die drei ACEs mit korrekten AccessMask und AceFlags
                foreach ($requiredAce in $requiredAces) {
                    $ace = ([WMIClass]"Win32_ACE").CreateInstance()
                    $ace.AccessMask = $requiredAce.AccessMask
                    $ace.AceType = 0  # ACCESS_ALLOWED_ACE_TYPE
                    $ace.AceFlags = $requiredAce.AceFlags
                    $ace.Trustee = $trustee
                    [void]$newDacl.Add($ace)
                }
                
                $descriptor.DACL = $newDacl.ToArray()
                $setResult = $printerWmi.SetSecurityDescriptor($descriptor)
                
                if ($setResult.ReturnValue -eq 0) {
                    if ($groupAceFound) {
                        Write-Host "  [OK] Berechtigungen aktualisiert (entfernt: $($existingAces.Count), hinzugefügt: 3)" -ForegroundColor Green
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
        
    } catch {
        $errorMsg = if ($_.Exception.Message) { $_.Exception.Message } else { $_.Exception.ToString() }
        Write-Host "  [FEHLER] Beim Erstellen der Gruppe: $errorMsg" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Neue Gruppen erstellt: $createdCount" -ForegroundColor Green
Write-Host "Bereits vorhandene Gruppen: $existingCount" -ForegroundColor Gray
Write-Host "Gruppen zugewiesen: $assignedCount" -ForegroundColor Green
Write-Host "Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Gesamt Drucker: $($printers.Count)" -ForegroundColor White
