# ==================================================================
# Diagnose-Script für Drucker-Installationsprobleme
# Prüft alle möglichen Ursachen, warum Drucker nicht installiert werden
# ==================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$GPOName = "Drucker - <PRINT-SERVER-1>-01 - Alle Drucker",
    
    [Parameter(Mandatory=$false)]
    [string]$TestUser = "uebergabe",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "(Join-Path $PSScriptRoot "Diagnose-Output")"
)

$ErrorActionPreference = "Continue"

# Erstelle Output-Verzeichnis
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$logFile = Join-Path $OutputDir "Diagnose-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
$csvFile = Join-Path $OutputDir "Diagnose-Ergebnisse-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoConsole
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    if (-not $NoConsole) {
        Write-Host $logMessage
    }
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
}

function Write-Section {
    param([string]$Title)
    Write-Log "" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "  $Title" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "" "INFO"
}

Write-Section "Starte Diagnose für Benutzer: $TestUser"

# Prüfe Module
Write-Section "Prüfe Module"
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Log "GroupPolicy-Modul geladen" "SUCCESS"
} catch {
    Write-Log "FEHLER: GroupPolicy-Modul nicht verfügbar: $($_.Exception.Message)" "ERROR"
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory-Modul geladen" "SUCCESS"
} catch {
    Write-Log "FEHLER: ActiveDirectory-Modul nicht verfügbar: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ==================================================================
# 1. Prüfe Benutzer und Gruppen
# ==================================================================
Write-Section "1. Prüfe Benutzer und zugewiesene Gruppen"

$user = $null
try {
    $user = Get-ADUser -Identity $TestUser -Properties MemberOf -ErrorAction Stop
    Write-Log "Benutzer gefunden: $($user.Name) ($($user.SamAccountName))" "SUCCESS"
} catch {
    Write-Log "FEHLER: Benutzer '$TestUser' nicht gefunden: $($_.Exception.Message)" "ERROR"
    exit 1
}

$userGroups = @()
$userGroupSids = @()
try {
    $groupDNs = $user.MemberOf
    Write-Log "Benutzer ist Mitglied von $($groupDNs.Count) Gruppen" "INFO"
    
    foreach ($groupDN in $groupDNs) {
        try {
            $group = Get-ADGroup -Identity $groupDN -Properties SID, Description -ErrorAction Stop
            $userGroups += $group
            $userGroupSids += $group.SID.Value
            Write-Log "  Gruppe: $($group.Name) (SID: $($group.SID.Value))" "INFO"
        } catch {
            Write-Log "  WARNUNG: Konnte Gruppe nicht abrufen: $groupDN" "WARNING"
        }
    }
} catch {
    Write-Log "FEHLER: Konnte Gruppen nicht abrufen: $($_.Exception.Message)" "ERROR"
}

# Filtere nur Drucker-Gruppen (basierend auf Namensschema oder OU)
$printerGroups = $userGroups | Where-Object { 
    $_.DistinguishedName -like "*$OUPath*" -or
    $_.Name -like "<LOCATION>*" -or
    $_.Name -like "*BRO-*" -or
    $_.Name -like "*KYO-*" -or
    $_.Name -like "*KON-*" -or
    $_.Name -like "*CAN-*"
}

Write-Log "" "INFO"
Write-Log "Drucker-relevante Gruppen: $($printerGroups.Count)" "INFO"
foreach ($pg in $printerGroups) {
    Write-Log "  - $($pg.Name)" "INFO"
}

# ==================================================================
# 2. Prüfe Drucker auf Server
# ==================================================================
Write-Section "2. Prüfe Drucker auf Server: $ComputerName"

$serverPrinters = @()
try {
    $serverPrinters = Get-Printer -ComputerName $ComputerName -ErrorAction Stop | Where-Object { $_.Shared -eq $true }
    Write-Log "Gefunden: $($serverPrinters.Count) geteilte Drucker auf Server" "SUCCESS"
} catch {
    Write-Log "FEHLER: Konnte Drucker nicht abrufen: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Erstelle Hash-Table für schnellen Zugriff
$serverPrintersHash = @{}
foreach ($printer in $serverPrinters) {
    $serverPrintersHash[$printer.Name] = $printer
    $serverPrintersHash[$printer.ShareName] = $printer
}

# ==================================================================
# 3. Prüfe GPO
# ==================================================================
Write-Section "3. Prüfe GPO: $GPOName"

$gpo = $null
try {
    $gpo = Get-GPO -Name $GPOName -ErrorAction Stop
    Write-Log "GPO gefunden: $($gpo.DisplayName)" "SUCCESS"
    Write-Log "  GPO-GUID: $($gpo.Id)" "INFO"
    Write-Log "  Status: $($gpo.GpoStatus)" "INFO"
} catch {
    Write-Log "FEHLER: GPO nicht gefunden: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Prüfe GPO-Verknüpfungen
try {
    $domain = Get-ADDomain
    $allLinks = Get-GPInheritance -Target $domain.DistinguishedName -ErrorAction SilentlyContinue
    $gpoLinks = $allLinks | Where-Object { $_.GpoId -eq $gpo.Id }
    
    if ($gpoLinks) {
        Write-Log "GPO ist verknüpft mit:" "INFO"
        foreach ($link in $gpoLinks) {
            Write-Log "  - $($link.Target)" "INFO"
        }
    } else {
        Write-Log "WARNUNG: GPO ist nicht mit einer OU verknüpft!" "WARNING"
    }
} catch {
    Write-Log "WARNUNG: Konnte GPO-Verknüpfungen nicht prüfen: $($_.Exception.Message)" "WARNING"
}

# ==================================================================
# 4. Analysiere GPO-XML
# ==================================================================
Write-Section "4. Analysiere GPO-XML-Datei"

$domainName = (Get-ADDomain).DNSRoot
$gpoXmlPath = "\\$domainName\SYSVOL\$domainName\Policies\{$($gpo.Id)}\User\Preferences\Printers\Printers.xml"

$gpoPrinters = @()
$gpoPrintersByGroup = @{}

if (Test-Path $gpoXmlPath) {
    Write-Log "XML-Datei gefunden: $gpoXmlPath" "SUCCESS"
    
    try {
        [xml]$gpoXml = Get-Content $gpoXmlPath -Encoding UTF8
        
        if ($gpoXml.DocumentElement) {
            $sharedPrinters = $gpoXml.SelectNodes("//SharedPrinter")
            Write-Log "Gefunden: $($sharedPrinters.Count) SharedPrinter-Einträge in GPO" "INFO"
            
            foreach ($sp in $sharedPrinters) {
                $printerName = $sp.GetAttribute("name")
                $properties = $sp.SelectSingleNode("Properties")
                $filters = $sp.SelectSingleNode("Filters")
                
                if ($properties) {
                    $printerPath = $properties.GetAttribute("path")
                    $action = $properties.GetAttribute("action")
                    
                    # Extrahiere Druckernamen aus UNC-Pfad
                    $shareName = ""
                    if ($printerPath -match "\\\\$ComputerName\\(.+)") {
                        $shareName = $matches[1]
                    }
                    
                    # Prüfe Item-Level Targeting
                    $targetGroup = $null
                    $targetGroupSid = $null
                    $targetGroupName = $null
                    
                    if ($filters) {
                        $filterGroup = $filters.SelectSingleNode("FilterGroup[@not='0']")
                        if ($filterGroup) {
                            $targetGroupName = $filterGroup.GetAttribute("name")
                            $targetGroupSid = $filterGroup.GetAttribute("sid")
                            
                            # Extrahiere Gruppennamen (ohne Domain-Präfix)
                            if ($targetGroupName -match "^[^\\]+\\(.+)") {
                                $targetGroupName = $matches[1]
                            }
                            
                            # Finde Gruppe in AD
                            try {
                                $targetGroup = Get-ADGroup -Filter "SID -eq '$targetGroupSid'" -ErrorAction SilentlyContinue
                            } catch {
                                # Versuche mit Name
                                try {
                                    $targetGroup = Get-ADGroup -Filter "Name -eq '$targetGroupName'" -ErrorAction SilentlyContinue
                                } catch { }
                            }
                        }
                    }
                    
                    $gpoPrinterInfo = [PSCustomObject]@{
                        PrinterName = $printerName
                        ShareName = $shareName
                        PrinterPath = $printerPath
                        Action = $action
                        TargetGroupName = $targetGroupName
                        TargetGroupSid = $targetGroupSid
                        TargetGroupFound = ($targetGroup -ne $null)
                        HasFilters = ($filters -ne $null)
                        ExistsOnServer = $serverPrintersHash.ContainsKey($printerName) -or $serverPrintersHash.ContainsKey($shareName)
                    }
                    
                    $gpoPrinters += $gpoPrinterInfo
                    
                    # Speichere nach Gruppe
                    if ($targetGroupName) {
                        if (-not $gpoPrintersByGroup.ContainsKey($targetGroupName)) {
                            $gpoPrintersByGroup[$targetGroupName] = @()
                        }
                        $gpoPrintersByGroup[$targetGroupName] += $gpoPrinterInfo
                    }
                    
                    Write-Log "  Drucker: $printerName" "INFO"
                    Write-Log "    Share: $shareName" "INFO"
                    Write-Log "    Action: $action" "INFO"
                    Write-Log "    Target-Gruppe: $targetGroupName" "INFO"
                    Write-Log "    Gruppe gefunden: $($targetGroup -ne $null)" "INFO"
                    Write-Log "    Auf Server: $($gpoPrinterInfo.ExistsOnServer)" "INFO"
                }
            }
        } else {
            Write-Log "FEHLER: XML hat kein Root-Element!" "ERROR"
        }
    } catch {
        Write-Log "FEHLER: Konnte XML nicht analysieren: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "FEHLER: XML-Datei nicht gefunden: $gpoXmlPath" "ERROR"
}

# ==================================================================
# 5. Prüfe Berechtigungen auf Druckern
# ==================================================================
Write-Section "5. Prüfe Berechtigungen auf Druckern"

$printerPermissions = @()

foreach ($printerGroup in $printerGroups) {
    $groupName = $printerGroup.Name
    
    # Finde entsprechenden Drucker auf Server
    $matchingPrinter = $serverPrinters | Where-Object { 
        $_.Name -eq $groupName -or 
        $_.ShareName -eq $groupName 
    } | Select-Object -First 1
    
    if ($matchingPrinter) {
        Write-Log "Prüfe Berechtigungen für: $($matchingPrinter.Name)" "INFO"
        
        try {
            $printerWmi = Get-WmiObject -ComputerName $ComputerName -Class Win32_Printer -Filter "Name='$($matchingPrinter.Name -replace "'", "''")'" -ErrorAction Stop
            
            if ($printerWmi) {
                $sdResult = $printerWmi.GetSecurityDescriptor()
                if ($sdResult.ReturnValue -eq 0) {
                    $descriptor = $sdResult.Descriptor
                    $groupSid = $printerGroup.SID.Value
                    
                    $hasPermission = $false
                    $aceCount = 0
                    
                    foreach ($ace in $descriptor.DACL) {
                        if ($ace.Trustee.SIDString -eq $groupSid) {
                            $hasPermission = $true
                            $aceCount++
                            Write-Log "    ACE gefunden: AccessMask=$($ace.AccessMask), AceFlags=$($ace.AceFlags)" "INFO"
                        }
                    }
                    
                    $printerPermissions += [PSCustomObject]@{
                        PrinterName = $matchingPrinter.Name
                        GroupName = $groupName
                        GroupSid = $groupSid
                        HasPermission = $hasPermission
                        AceCount = $aceCount
                    }
                    
                    if ($hasPermission) {
                        Write-Log "    [OK] Gruppe hat Berechtigungen ($aceCount ACEs)" "SUCCESS"
                    } else {
                        Write-Log "    [FEHLER] Gruppe hat KEINE Berechtigungen!" "ERROR"
                    }
                } else {
                    Write-Log "    [WARNUNG] Konnte Berechtigungen nicht abrufen (ReturnValue: $($sdResult.ReturnValue))" "WARNING"
                }
            }
        } catch {
            Write-Log "    [FEHLER] Fehler beim Prüfen der Berechtigungen: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "  [WARNUNG] Kein passender Drucker auf Server für Gruppe: $groupName" "WARNING"
    }
}

# ==================================================================
# 6. Vergleich: Gruppen vs. Drucker vs. GPO
# ==================================================================
Write-Section "6. Vergleich: Gruppen vs. Drucker vs. GPO"

$comparisonResults = @()

foreach ($printerGroup in $printerGroups) {
    $groupName = $printerGroup.Name
    $groupSid = $printerGroup.SID.Value
    
    # Prüfe ob Drucker auf Server existiert
    $printerOnServer = $serverPrinters | Where-Object { 
        $_.Name -eq $groupName -or 
        $_.ShareName -eq $groupName 
    } | Select-Object -First 1
    
    # Prüfe ob in GPO konfiguriert
    $inGPO = $gpoPrinters | Where-Object { 
        $_.TargetGroupName -eq $groupName -or
        $_.TargetGroupSid -eq $groupSid
    } | Select-Object -First 1
    
    # Prüfe Berechtigungen
    $hasPermission = ($printerPermissions | Where-Object { 
        $_.GroupName -eq $groupName 
    } | Select-Object -First 1).HasPermission
    
    $status = "OK"
    $issues = @()
    
    if (-not $printerOnServer) {
        $status = "FEHLER"
        $issues += "Drucker existiert nicht auf Server"
    }
    
    if (-not $inGPO) {
        $status = "FEHLER"
        $issues += "Drucker nicht in GPO konfiguriert"
    } elseif (-not $inGPO.TargetGroupFound) {
        $status = "FEHLER"
        $issues += "Target-Gruppe in GPO nicht gefunden"
    }
    
    if ($printerOnServer -and -not $hasPermission) {
        $status = "FEHLER"
        $issues += "Gruppe hat keine Berechtigungen auf Drucker"
    }
    
    $comparisonResults += [PSCustomObject]@{
        GroupName = $groupName
        GroupSid = $groupSid
        PrinterOnServer = ($printerOnServer -ne $null)
        PrinterName = if ($printerOnServer) { $printerOnServer.Name } else { "" }
        InGPO = ($inGPO -ne $null)
        GPOGroupFound = if ($inGPO) { $inGPO.TargetGroupFound } else { $false }
        HasPermission = $hasPermission
        Status = $status
        Issues = ($issues -join "; ")
    }
    
    Write-Log "Gruppe: $groupName" "INFO"
    Write-Log "  Auf Server: $($printerOnServer -ne $null)" "INFO"
    Write-Log "  In GPO: $($inGPO -ne $null)" "INFO"
    Write-Log "  Berechtigungen: $hasPermission" "INFO"
    Write-Log "  Status: $status" $(if ($status -eq "OK") { "SUCCESS" } else { "ERROR" })
    if ($issues.Count -gt 0) {
        Write-Log "  Probleme: $($issues -join ', ')" "ERROR"
    }
}

# ==================================================================
# 7. Zusammenfassung
# ==================================================================
Write-Section "7. Zusammenfassung"

Write-Log "Benutzer: $TestUser" "INFO"
Write-Log "Zugewiesene Drucker-Gruppen: $($printerGroups.Count)" "INFO"
Write-Log "Drucker auf Server: $($serverPrinters.Count)" "INFO"
Write-Log "Drucker in GPO: $($gpoPrinters.Count)" "INFO"
Write-Log "" "INFO"

$okCount = ($comparisonResults | Where-Object { $_.Status -eq "OK" }).Count
$errorCount = ($comparisonResults | Where-Object { $_.Status -eq "FEHLER" }).Count

Write-Log "OK: $okCount" "SUCCESS"
Write-Log "FEHLER: $errorCount" "ERROR"
Write-Log "" "INFO"

# Exportiere Ergebnisse
try {
    $comparisonResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Ergebnisse exportiert nach: $csvFile" "SUCCESS"
} catch {
    Write-Log "FEHLER: Konnte Ergebnisse nicht exportieren: $($_.Exception.Message)" "ERROR"
}

# Detaillierte Ausgabe für fehlerhafte Gruppen
Write-Section "Detaillierte Analyse fehlerhafter Gruppen"

$errorGroups = $comparisonResults | Where-Object { $_.Status -eq "FEHLER" }

if ($errorGroups.Count -gt 0) {
    foreach ($errorGroup in $errorGroups) {
        Write-Log "=== $($errorGroup.GroupName) ===" "ERROR"
        Write-Log "Probleme: $($errorGroup.Issues)" "ERROR"
        Write-Log "" "INFO"
        
        # Spezifische Prüfungen
        if (-not $errorGroup.PrinterOnServer) {
            Write-Log "  → Prüfe ob Drucker auf Server existiert oder anderer Name verwendet wird" "INFO"
            Write-Log "    Suche nach ähnlichen Namen..." "INFO"
            $similarPrinters = $serverPrinters | Where-Object { 
                $_.Name -like "*$($errorGroup.GroupName)*" -or
                $errorGroup.GroupName -like "*$($_.Name)*"
            }
            if ($similarPrinters) {
                foreach ($sp in $similarPrinters) {
                    Write-Log "    Gefunden: $($sp.Name)" "INFO"
                }
            } else {
                Write-Log "    Keine ähnlichen Namen gefunden" "WARNING"
            }
        }
        
        if (-not $errorGroup.InGPO) {
            Write-Log "  → Drucker ist nicht in GPO konfiguriert" "INFO"
            Write-Log "    Führe 6.2-Erstelle-Drucker-GPO.ps1 aus, um GPO zu aktualisieren" "INFO"
        }
        
        if ($errorGroup.InGPO -and -not $errorGroup.GPOGroupFound) {
            Write-Log "  → Target-Gruppe in GPO nicht gefunden (SID-Mismatch?)" "INFO"
        }
        
        if ($errorGroup.PrinterOnServer -and -not $errorGroup.HasPermission) {
            Write-Log "  → Gruppe hat keine Berechtigungen auf Drucker" "INFO"
            Write-Log "    Führe 6.1-Erstelle-Drucker-Sicherheitsgruppen.ps1 aus, um Berechtigungen zu setzen" "INFO"
        }
        
        Write-Log "" "INFO"
    }
} else {
    Write-Log "Alle Gruppen sind korrekt konfiguriert!" "SUCCESS"
}

Write-Log "" "INFO"
Write-Log "Diagnose abgeschlossen. Log-Datei: $logFile" "INFO"
Write-Log "CSV-Export: $csvFile" "INFO"
