# ==================================================================
# Phase 1: Bestandsaufnahme aller Sicherheitsgruppen von Druckern
# Durchsucht alle Drucker auf den Print-Servern nach zugewiesenen Sicherheitsgruppen
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OldServers = @("<PRINT-SERVER-1>", "<PRINT-SERVER-2>", "<PRINT-SERVER-3>")
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\1.3-Bestandsaufnahme-Sicherheitsgruppen_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Verzeichnisse
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (-not (Test-Path "$OutputDir\Logs")) { New-Item -ItemType Directory -Path "$OutputDir\Logs" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

# Prüfe ob ActiveDirectory-Modul verfügbar ist
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory-Modul geladen" "SUCCESS"
}
catch {
    Write-Log "FEHLER: ActiveDirectory-Modul konnte nicht geladen werden. Bitte installieren Sie RSAT: Active Directory Domain Services Tools" "ERROR"
    exit 1
}

Write-Log "=== Bestandsaufnahme Sicherheitsgruppen von Druckern gestartet ===" "INFO"
Write-Log "Zu prüfende Server: $($OldServers -join ', ')" "INFO"

$allResults = @()
$processedGroups = @{}  # Dictionary um doppelte Gruppen zu vermeiden

# Funktion zum Abrufen der Drucker-Berechtigungen über WMI
function Get-PrinterPermissions {
    param(
        [string]$ComputerName,
        [string]$PrinterName
    )
    
    try {
        # Verwende WMI um die Drucker-Berechtigungen zu erhalten
        $printer = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
        
        if (-not $printer) {
            return $null
        }
        
        # Hole die Security Descriptor über WMI
        $sd = $printer.GetSecurityDescriptor()
        
        if ($sd.ReturnValue -ne 0) {
            return $null
        }
        
        return $sd.Descriptor
    }
    catch {
        return $null
    }
}

foreach ($server in $OldServers) {
    Write-Host ""
    Write-Host "=== Server: $server ===" -ForegroundColor Cyan
    Write-Log "Verarbeite Server: $server" "INFO"
    
    try {
        # Prüfe ob Server erreichbar ist
        if (-not (Test-Connection -ComputerName $server -Count 1 -Quiet)) {
            Write-Log "Server $server ist nicht erreichbar!" "ERROR"
            Write-Host "WARNUNG: Server $server ist nicht erreichbar!" -ForegroundColor Yellow
            continue
        }
        
        # Hole alle Drucker vom Server
        $printers = Get-Printer -ComputerName $server -ErrorAction Stop
        Write-Log "Gefundene Drucker auf $server : $($printers.Count)" "INFO"
        Write-Host "Gefundene Drucker: $($printers.Count)" -ForegroundColor Green
        
        foreach ($printer in $printers) {
            try {
                Write-Log "  Prüfe Drucker: $($printer.Name)" "INFO"
                
                # Methode 1: Direkter WMI-Zugriff (primär - funktioniert auch bei Offline-Druckern)
                $permissions = $null
                
                try {
                    # Direkter WMI-Zugriff von außen (ohne Invoke-Command) - PRIMÄRE METHODE
                    $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $server -Filter "Name='$($printer.Name.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                    
                    if ($wmiPrinter) {
                        # Versuche Security Descriptor abzurufen
                        $sd = $wmiPrinter.GetSecurityDescriptor()
                        
                        if ($sd.ReturnValue -eq 0) {
                            # Extrahiere die DACL (Discretionary Access Control List)
                            $dacl = $sd.Descriptor.DACL
                            $permissions = @()
                            
                            foreach ($ace in $dacl) {
                                $trustee = $ace.Trustee
                                $identity = $trustee.Name
                                $domain = $trustee.Domain
                                
                                if ($domain) {
                                    $fullName = "$domain\$identity"
                                }
                                else {
                                    $fullName = $identity
                                }
                                
                                $permissions += [PSCustomObject]@{
                                    Identity = $fullName
                                    AccessMask = $ace.AccessMask
                                    AceType = $ace.AceType
                                }
                            }
                        }
                        else {
                            Write-Log "    GetSecurityDescriptor fehlgeschlagen - ReturnValue: $($sd.ReturnValue)" "WARNING"
                        }
                    }
                    else {
                        Write-Log "    WMI Drucker-Objekt nicht gefunden" "WARNING"
                    }
                }
                catch {
                    Write-Log "    Fehler beim direkten WMI-Zugriff: $($_.Exception.Message)" "WARNING"
                }
                
                # Methode 2: Fallback über Invoke-Command (Alternative, falls direkter WMI-Zugriff fehlschlägt)
                if (-not $permissions -or $permissions.Count -eq 0) {
                    try {
                        $scriptBlock = {
                            param($PrinterName)
                            
                            try {
                                $wmiPrinter = Get-WmiObject -Class Win32_Printer -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                                if (-not $wmiPrinter) {
                                    return $null
                                }
                                
                                $sd = $wmiPrinter.GetSecurityDescriptor()
                                if ($sd.ReturnValue -ne 0) {
                                    return $null
                                }
                                
                                $dacl = $sd.Descriptor.DACL
                                $permissions = @()
                                
                                foreach ($ace in $dacl) {
                                    $trustee = $ace.Trustee
                                    $identity = $trustee.Name
                                    $domain = $trustee.Domain
                                    
                                    if ($domain) {
                                        $fullName = "$domain\$identity"
                                    }
                                    else {
                                        $fullName = $identity
                                    }
                                    
                                    $permissions += [PSCustomObject]@{
                                        Identity = $fullName
                                        AccessMask = $ace.AccessMask
                                        AceType = $ace.AceType
                                    }
                                }
                                
                                return $permissions
                            }
                            catch {
                                return $null
                            }
                        }
                        
                        $permissions = Invoke-Command -ComputerName $server -ScriptBlock $scriptBlock -ArgumentList $printer.Name -ErrorAction SilentlyContinue
                    }
                    catch {
                        # Ignoriere Fehler beim Fallback
                    }
                }
                
                if (-not $permissions -or $permissions.Count -eq 0) {
                    Write-Log "    Konnte Berechtigungen nicht abrufen" "WARNING"
                    continue
                }
                
                # Verarbeite jede Berechtigung
                foreach ($perm in $permissions) {
                    try {
                        $identityName = $perm.Identity
                        
                        if (-not $identityName) {
                            continue
                        }
                        
                        # Überspringe bekannte System-Accounts
                        $skipAccounts = @(
                            "CREATOR OWNER",
                            "ERSTELLER-BESITZER",
                            "CREATOR-OWNER",
                            "NT AUTHORITY\SYSTEM",
                            "NT-AUTORITÄT\SYSTEM",
                            "BUILTIN\Administrators",
                            "VORDEFINIERT\Administratoren",
                            "ALL APPLICATION PACKAGES",
                            "ALLE ANWENDUNGSPAKETE",
                            "$server\Administrators"
                        )
                        
                        $shouldSkip = $false
                        foreach ($skip in $skipAccounts) {
                            if ($identityName -like "*$skip*") {
                                $shouldSkip = $true
                                break
                            }
                        }
                        
                        if ($shouldSkip) {
                            continue
                        }
                        
                        # Extrahiere Gruppenname (kann Domain\Group oder nur Group sein)
                        $groupName = $identityName
                        if ($identityName -match "\\") {
                            $groupName = $identityName.Split('\')[-1]
                        }
                        
                        # Prüfe ob es eine Gruppe ist
                        $isGroup = $false
                        $groupDN = $null
                        $groupInfo = $null
                        
                        try {
                            # Versuche als Gruppe zu finden
                            $groupInfo = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                            
                            if (-not $groupInfo) {
                                # Versuche mit SamAccountName
                                $groupInfo = Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction SilentlyContinue
                            }
                            
                            if (-not $groupInfo -and $identityName -match "\\") {
                                # Versuche mit Domain\Group Format
                                $groupPart = $identityName.Split('\')[1]
                                $groupInfo = Get-ADGroup -Filter "Name -eq '$groupPart'" -ErrorAction SilentlyContinue
                            }
                            
                            if ($groupInfo) {
                                $isGroup = $true
                                $groupDN = $groupInfo.DistinguishedName
                            }
                            else {
                                # Prüfe ob es ein Benutzer ist
                                $userInfo = Get-ADUser -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                                if ($userInfo) {
                                    # Es ist ein Benutzer, überspringe
                                    continue
                                }
                            }
                        }
                        catch {
                            # Ignoriere Fehler beim Suchen
                        }
                        
                        # Wenn es eine Gruppe ist, verarbeite sie
                        if ($isGroup -and $groupInfo) {
                            $groupKey = $groupDN
                            
                            # Hole Mitglieder der Gruppe (falls noch nicht geschehen)
                            if (-not $processedGroups.ContainsKey($groupKey)) {
                                Write-Log "    Gefundene Sicherheitsgruppe: $($groupInfo.Name)" "INFO"
                                
                                $members = @()
                                try {
                                    $groupMembers = Get-ADGroupMember -Identity $groupDN -ErrorAction SilentlyContinue
                                    if ($groupMembers) {
                                        foreach ($member in $groupMembers) {
                                            $memberName = $member.Name
                                            if ($member.ObjectClass -eq "user") {
                                                $memberName = "$($member.Name) ($($member.SamAccountName))"
                                            }
                                            $members += $memberName
                                        }
                                    }
                                }
                                catch {
                                    Write-Log "      Konnte Mitglieder nicht abrufen: $($_.Exception.Message)" "WARNING"
                                }
                                
                                $processedGroups[$groupKey] = @{
                                    GroupName = $groupInfo.Name
                                    DistinguishedName = $groupDN
                                    SamAccountName = $groupInfo.SamAccountName
                                    Members = $members
                                    MemberCount = $members.Count
                                }
                            }
                            
                            # Erstelle Eintrag für diesen Drucker
                            $result = [PSCustomObject]@{
                                Server = $server
                                PrinterName = $printer.Name
                                ShareName = $printer.ShareName
                                SecurityGroup = $groupInfo.Name
                                SecurityGroupDN = $groupDN
                                SecurityGroupSamAccountName = $groupInfo.SamAccountName
                                MemberCount = $processedGroups[$groupKey].MemberCount
                                Members = ($processedGroups[$groupKey].Members -join "; ")
                                AccessMask = $perm.AccessMask
                            }
                            
                            $allResults += $result
                        }
                    }
                    catch {
                        Write-Log "    Fehler beim Verarbeiten der Berechtigung: $($_.Exception.Message)" "WARNING"
                    }
                }
            }
            catch {
                Write-Log "Fehler beim Verarbeiten von Drucker $($printer.Name): $($_.Exception.Message)" "WARNING"
            }
        }
    }
    catch {
        Write-Log "FEHLER beim Abrufen der Drucker von $server : $($_.Exception.Message)" "ERROR"
    }
}

# Exportiere Ergebnisse
if ($allResults.Count -gt 0) {
    $csvFile = Join-Path $OutputDir "1.3-Sicherheitsgruppen-Bestandsaufnahme.csv"
    $allResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Sicherheitsgruppen-Export erstellt: $csvFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Zusammenfassung ===" -ForegroundColor Green
    Write-Host "Gefundene Drucker-Gruppen-Zuordnungen: $($allResults.Count)" -ForegroundColor Green
    
    $uniqueGroups = $allResults | Select-Object -Unique SecurityGroup
    Write-Host "Eindeutige Sicherheitsgruppen: $($uniqueGroups.Count)" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "=== Gefundene Sicherheitsgruppen ===" -ForegroundColor Yellow
    foreach ($group in $uniqueGroups) {
        $groupName = $group.SecurityGroup
        $printersForGroup = ($allResults | Where-Object { $_.SecurityGroup -eq $groupName }).PrinterName -join ", "
        Write-Host "  - $groupName" -ForegroundColor Cyan
        Write-Host "    Drucker: $printersForGroup" -ForegroundColor Gray
    }
}
else {
    Write-Host "KEINE Sicherheitsgruppen auf Druckern gefunden!" -ForegroundColor Yellow
    Write-Log "KEINE Sicherheitsgruppen auf Druckern gefunden" "INFO"
    
    # Erstelle leere CSV-Datei trotzdem
    $csvFile = Join-Path $OutputDir "1.3-Sicherheitsgruppen-Bestandsaufnahme.csv"
    $allResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Leere CSV-Datei erstellt: $csvFile" "INFO"
}

Write-Host ""
Write-Host "Export-Datei: $(Join-Path $OutputDir '1.3-Sicherheitsgruppen-Bestandsaufnahme.csv')" -ForegroundColor Cyan

Write-Log "=== Bestandsaufnahme Sicherheitsgruppen abgeschlossen ===" "INFO"
