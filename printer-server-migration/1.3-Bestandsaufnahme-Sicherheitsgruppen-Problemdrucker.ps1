# ==================================================================
# Problemdrucker-Analyse: Prüft nur die Drucker mit Berechtigungsproblemen
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\1.3-Bestandsaufnahme-Sicherheitsgruppen-Problemdrucker_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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

Write-Log "=== Problemdrucker-Analyse gestartet ===" "INFO"

# Liste der betroffenen Drucker (aus dem Log extrahiert)
$problemPrinters = @(
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother MFC-J5625DW ABW Kupferdreh"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN Tagung"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN Frontoffice"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN DR-900-0002"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN DR-900-0001"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN DR-100-0005"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L5100DN Backoffice"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2445DW DR-500-0001"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2370DN Hausmeister Schule"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2370DN DR-200-0002"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2370DN DR-100-0002"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2370DN Buchhaltung FiBu01"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother HL-L2350DW DR-100-0009"},
    @{Server = "<PRINT-SERVER-2>"; Name = "Brother DCP-L3550CDW AWIEW"}
)

Write-Log "Zu prüfende Problemdrucker: $($problemPrinters.Count)" "INFO"

$allResults = @()
$processedGroups = @{}  # Dictionary um doppelte Gruppen zu vermeiden

# Funktion zum Abrufen der Security Descriptors über verschiedene Methoden
function Get-PrinterSecurityDescriptor {
    param(
        [string]$ComputerName,
        [string]$PrinterName
    )
    
    $result = @{
        Method = $null
        PrinterFound = $false
        WmiPrinterFound = $false
        SecurityDescriptorSuccess = $false
        ReturnValue = $null
        ErrorMessage = $null
        Permissions = @()
        PrinterStatus = $null
        PrinterState = $null
        DriverName = $null
        PortName = $null
    }
    
    # Methode 1: Direkter WMI-Zugriff von außen (ohne Invoke-Command)
    try {
        Write-Log "    Versuche direkten WMI-Zugriff..." "INFO"
        $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
        
        if ($wmiPrinter) {
            $result.WmiPrinterFound = $true
            $result.PrinterStatus = $wmiPrinter.PrinterStatus
            $result.PrinterState = $wmiPrinter.PrinterState
            $result.DriverName = $wmiPrinter.DriverName
            $result.PortName = $wmiPrinter.PortName
            $result.Method = "WMI-Direct"
            
            # Versuche Security Descriptor abzurufen
            try {
                $sd = $wmiPrinter.GetSecurityDescriptor()
                $result.ReturnValue = $sd.ReturnValue
                
                if ($sd.ReturnValue -eq 0) {
                    $result.SecurityDescriptorSuccess = $true
                    
                    # Extrahiere die DACL
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
                    
                    $result.Permissions = $permissions
                    Write-Log "    Erfolgreich über direkten WMI-Zugriff" "SUCCESS"
                    return $result
                }
                else {
                    Write-Log "    GetSecurityDescriptor ReturnValue: $($sd.ReturnValue)" "WARNING"
                }
            }
            catch {
                Write-Log "    Exception bei GetSecurityDescriptor: $($_.Exception.Message)" "WARNING"
            }
        }
        else {
            Write-Log "    WMI-Direktzugriff: Drucker nicht gefunden" "WARNING"
        }
    }
    catch {
        Write-Log "    Fehler bei direktem WMI-Zugriff: $($_.Exception.Message)" "WARNING"
    }
    
    # Methode 2: Registry-Zugriff (Security Descriptors werden in der Registry gespeichert)
    try {
        Write-Log "    Versuche Registry-Zugriff..." "INFO"
        
        # Prüfe ob Registry-Pfad existiert
        $regKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $ComputerName)
        if ($regKey) {
            $printerKey = $regKey.OpenSubKey("SYSTEM\CurrentControlSet\Control\Print\Printers\$PrinterName")
            if ($printerKey) {
                $result.PrinterFound = $true
                $result.Method = "Registry"
                Write-Log "    Registry-Pfad gefunden" "INFO"
                
                # Versuche Security Descriptor aus Registry zu lesen
                $securityKey = $printerKey.OpenSubKey("Security")
                if ($securityKey) {
                    # Security Descriptor ist als Binärdaten gespeichert
                    # Wir müssen es über WMI oder .NET API dekodieren
                    Write-Log "    Security-Key in Registry gefunden" "INFO"
                    
                    # Versuche über Invoke-Command die Security Descriptor zu dekodieren
                    $scriptBlock = {
                        param($PrinterName)
                        try {
                            $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
                            if ($printer) {
                                # Verwende .NET PrintSystemObject um Security Descriptor zu bekommen
                                $printQueue = New-Object System.Printing.PrintQueue -ArgumentList $printer.Name, $false
                                if ($printQueue) {
                                    $sd = $printQueue.GetSecurityDescriptor()
                                    return $sd
                                }
                            }
                        }
                        catch {
                            return $null
                        }
                        return $null
                    }
                    
                    try {
                        $sdData = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $PrinterName -ErrorAction SilentlyContinue
                        if ($sdData) {
                            Write-Log "    Security Descriptor über Registry + .NET API gefunden" "SUCCESS"
                            # Hier müssten wir die SD-Daten dekodieren - komplex, daher zurück zu Methode 3
                        }
                    }
                    catch {
                        Write-Log "    Fehler bei Registry-Dekodierung: $($_.Exception.Message)" "WARNING"
                    }
                    
                    $securityKey.Close()
                }
                $printerKey.Close()
            }
            $regKey.Close()
        }
    }
    catch {
        Write-Log "    Fehler bei Registry-Zugriff: $($_.Exception.Message)" "WARNING"
    }
    
    # Methode 3: Invoke-Command mit CIM (neuere Alternative zu WMI)
    try {
        Write-Log "    Versuche CIM-Zugriff über Invoke-Command..." "INFO"
        $scriptBlock = {
            param($PrinterName)
            
            try {
                # Versuche CIM
                $cimPrinter = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                if ($cimPrinter) {
                    # CIM unterstützt GetSecurityDescriptor nicht direkt, daher WMI
                    $wmiPrinter = Get-WmiObject -Class Win32_Printer -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                    if ($wmiPrinter) {
                        $sd = $wmiPrinter.GetSecurityDescriptor()
                        if ($sd.ReturnValue -eq 0) {
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
                            
                            return @{
                                Success = $true
                                Permissions = $permissions
                                ReturnValue = $sd.ReturnValue
                            }
                        }
                    }
                }
            }
            catch {
                return @{
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
            
            return @{
                Success = $false
                Error = "Drucker nicht gefunden"
            }
        }
        
        $cimResult = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $PrinterName -ErrorAction SilentlyContinue
        
        if ($cimResult -and $cimResult.Success) {
            $result.SecurityDescriptorSuccess = $true
            $result.Permissions = $cimResult.Permissions
            $result.ReturnValue = $cimResult.ReturnValue
            $result.Method = "CIM-InvokeCommand"
            Write-Log "    Erfolgreich über CIM + Invoke-Command" "SUCCESS"
            return $result
        }
        else {
            Write-Log "    CIM-Zugriff fehlgeschlagen: $($cimResult.Error)" "WARNING"
        }
    }
    catch {
        Write-Log "    Fehler bei CIM-Zugriff: $($_.Exception.Message)" "WARNING"
    }
    
    # Alle Methoden fehlgeschlagen
    $result.ErrorMessage = "Alle Methoden zum Abrufen der Security Descriptors fehlgeschlagen"
    return $result
}

foreach ($printerInfo in $problemPrinters) {
    $server = $printerInfo.Server
    $printerName = $printerInfo.Name
    
    Write-Host ""
    Write-Host "=== Prüfe Drucker: $printerName auf $server ===" -ForegroundColor Cyan
    Write-Log "Prüfe Drucker: $printerName auf $server" "INFO"
    
    try {
        # Prüfe ob Server erreichbar ist
        if (-not (Test-Connection -ComputerName $server -Count 1 -Quiet)) {
            Write-Log "  Server $server ist nicht erreichbar!" "ERROR"
            Write-Host "WARNUNG: Server $server ist nicht erreichbar!" -ForegroundColor Yellow
            continue
        }
        
        # Prüfe ob Drucker auf dem Server existiert (optional - für Info)
        $printerExists = Get-Printer -ComputerName $server -Name $printerName -ErrorAction SilentlyContinue
        if ($printerExists) {
            Write-Log "  Drucker gefunden (Get-Printer) - Status: $($printerExists.PrinterStatus), State: $($printerExists.PrinterState)" "INFO"
        }
        else {
            Write-Log "  Drucker nicht über Get-Printer gefunden - versuche trotzdem WMI-Zugriff" "WARNING"
        }
        
        # Führe detaillierte Analyse durch mit mehreren Methoden
        $analysisResult = Get-PrinterSecurityDescriptor -ComputerName $server -PrinterName $printerName
        
        # Ausgabe der Analyseergebnisse
        Write-Host "  Analyseergebnisse:" -ForegroundColor Yellow
        Write-Host "    Verwendete Methode: $($analysisResult.Method)" -ForegroundColor $(if ($analysisResult.Method) { "Cyan" } else { "Red" })
        Write-Host "    Drucker gefunden: $($analysisResult.PrinterFound)" -ForegroundColor $(if ($analysisResult.PrinterFound) { "Green" } else { "Yellow" })
        Write-Host "    WMI Drucker gefunden: $($analysisResult.WmiPrinterFound)" -ForegroundColor $(if ($analysisResult.WmiPrinterFound) { "Green" } else { "Yellow" })
        Write-Host "    Security Descriptor erfolgreich: $($analysisResult.SecurityDescriptorSuccess)" -ForegroundColor $(if ($analysisResult.SecurityDescriptorSuccess) { "Green" } else { "Red" })
        
        if ($analysisResult.PrinterStatus) {
            Write-Log "    Drucker-Status: $($analysisResult.PrinterStatus)" "INFO"
        }
        if ($analysisResult.PrinterState) {
            Write-Log "    Drucker-State: $($analysisResult.PrinterState)" "INFO"
        }
        if ($analysisResult.DriverName) {
            Write-Log "    Treiber: $($analysisResult.DriverName)" "INFO"
        }
        if ($analysisResult.PortName) {
            Write-Log "    Port: $($analysisResult.PortName)" "INFO"
        }
        
        if ($null -ne $analysisResult.ReturnValue) {
            Write-Log "    GetSecurityDescriptor ReturnValue: $($analysisResult.ReturnValue)" "INFO"
            Write-Host "    ReturnValue: $($analysisResult.ReturnValue)" -ForegroundColor $(if ($analysisResult.ReturnValue -eq 0) { "Green" } else { "Red" })
        }
        
        if ($analysisResult.ErrorMessage) {
            Write-Log "    Fehler: $($analysisResult.ErrorMessage)" "WARNING"
            Write-Host "    Fehler: $($analysisResult.ErrorMessage)" -ForegroundColor Red
        }
        
        # Wenn Berechtigungen gefunden wurden, verarbeite sie
        if ($analysisResult.SecurityDescriptorSuccess -and $analysisResult.Permissions.Count -gt 0) {
            Write-Log "    Gefundene Berechtigungen: $($analysisResult.Permissions.Count)" "INFO"
            Write-Host "    Gefundene Berechtigungen: $($analysisResult.Permissions.Count)" -ForegroundColor Green
            
            foreach ($perm in $analysisResult.Permissions) {
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
                    
                    # Extrahiere Gruppenname
                    $groupName = $identityName
                    if ($identityName -match "\\") {
                        $groupName = $identityName.Split('\')[-1]
                    }
                    
                    # Prüfe ob es eine Gruppe ist
                    $isGroup = $false
                    $groupDN = $null
                    $groupInfo = $null
                    
                    try {
                        $groupInfo = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                        
                        if (-not $groupInfo) {
                            $groupInfo = Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction SilentlyContinue
                        }
                        
                        if (-not $groupInfo -and $identityName -match "\\") {
                            $groupPart = $identityName.Split('\')[1]
                            $groupInfo = Get-ADGroup -Filter "Name -eq '$groupPart'" -ErrorAction SilentlyContinue
                        }
                        
                        if ($groupInfo) {
                            $isGroup = $true
                            $groupDN = $groupInfo.DistinguishedName
                        }
                        else {
                            $userInfo = Get-ADUser -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                            if ($userInfo) {
                                continue
                            }
                        }
                    }
                    catch {
                        # Ignoriere Fehler beim Suchen
                    }
                    
                    if ($isGroup -and $groupInfo) {
                        $groupKey = $groupDN
                        
                        if (-not $processedGroups.ContainsKey($groupKey)) {
                            Write-Log "    Gefundene Sicherheitsgruppe: $($groupInfo.Name)" "INFO"
                            Write-Host "    Gefundene Sicherheitsgruppe: $($groupInfo.Name)" -ForegroundColor Green
                            
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
                        
                        $result = [PSCustomObject]@{
                            Server = $server
                            PrinterName = $printerName
                            ShareName = $printerExists.ShareName
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
        else {
            Write-Log "    Keine Berechtigungen gefunden oder konnten nicht abgerufen werden" "WARNING"
        }
    }
    catch {
        Write-Log "FEHLER beim Prüfen von Drucker $printerName auf $server : $($_.Exception.Message)" "ERROR"
        Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Zusammenfassung
Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Green
Write-Log "=== Zusammenfassung ===" "INFO"

if ($allResults.Count -gt 0) {
    Write-Host "Erfolgreich verarbeitete Drucker-Gruppen-Zuordnungen: $($allResults.Count)" -ForegroundColor Green
    Write-Log "Erfolgreich verarbeitete Drucker-Gruppen-Zuordnungen: $($allResults.Count)" "INFO"
    
    $uniqueGroups = $allResults | Select-Object -Unique SecurityGroup
    Write-Host "Eindeutige Sicherheitsgruppen: $($uniqueGroups.Count)" -ForegroundColor Green
    Write-Log "Eindeutige Sicherheitsgruppen: $($uniqueGroups.Count)" "INFO"
    
    # Exportiere Ergebnisse falls welche gefunden wurden
    $csvFile = Join-Path $OutputDir "Problemdrucker-Sicherheitsgruppen.csv"
    $allResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Ergebnisse exportiert: $csvFile" "SUCCESS"
    Write-Host "Ergebnisse exportiert: $csvFile" -ForegroundColor Cyan
}
else {
    Write-Host "Keine Sicherheitsgruppen auf den Problemdruckern gefunden!" -ForegroundColor Yellow
    Write-Log "Keine Sicherheitsgruppen auf den Problemdruckern gefunden" "INFO"
}

Write-Host ""
Write-Log "=== Problemdrucker-Analyse abgeschlossen ===" "INFO"

