# ==================================================================
# Phase 3: Analyse der Drucker-Adressen Ã¼ber Sicherheitsgruppen
# Ermittelt fÃ¼r jeden Drucker die hÃ¤ufigste Adresse und Abteilung
# basierend auf den Mitgliedern der zugewiesenen Sicherheitsgruppen
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$PrintersCSV = Join-Path $OutputDir "1.1-Drucker-Bestandsaufnahme.csv"
$SecurityGroupsCSV = Join-Path $OutputDir "1.3-Sicherheitsgruppen-Bestandsaufnahme.csv"
$LogFile = "$OutputDir\Logs\3.1-Analyse-Drucker-Adressen_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

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

# PrÃ¼fe ob ActiveDirectory-Modul verfÃ¼gbar ist
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory-Modul geladen" "SUCCESS"
}
catch {
    Write-Log "FEHLER: ActiveDirectory-Modul konnte nicht geladen werden. Bitte installieren Sie RSAT: Active Directory Domain Services Tools" "ERROR"
    exit 1
}

Write-Log "=== Analyse Drucker-Adressen gestartet ===" "INFO"

# Lade Drucker-Liste
if (-not (Test-Path $PrintersCSV)) {
    Write-Log "FEHLER: Drucker-CSV nicht gefunden: $PrintersCSV" "ERROR"
    exit 1
}

$printers = Import-Csv -Path $PrintersCSV -Delimiter ";" -Encoding UTF8
Write-Log "Geladene Drucker: $($printers.Count)" "INFO"

# Lade Sicherheitsgruppen-Zuordnung (falls vorhanden)
$securityGroupMapping = @{}
if (Test-Path $SecurityGroupsCSV) {
    Write-Log "Lade Sicherheitsgruppen-Zuordnung aus CSV..." "INFO"
    $securityGroups = Import-Csv -Path $SecurityGroupsCSV -Delimiter ";" -Encoding UTF8
    
    foreach ($sg in $securityGroups) {
        $printerName = $sg.PrinterName
        $server = $sg.Server
        $key = "$server|$printerName"
        
        if (-not $securityGroupMapping.ContainsKey($key)) {
            $securityGroupMapping[$key] = @()
        }
        
        # FÃ¼ge nur hinzu, wenn die Gruppe noch nicht vorhanden ist (vermeidet Duplikate durch verschiedene AccessMask-Werte)
        if ($securityGroupMapping[$key] -notcontains $sg.SecurityGroup) {
        $securityGroupMapping[$key] += $sg.SecurityGroup
        }
    }
    Write-Log "Geladene Sicherheitsgruppen-Zuordnungen: $($securityGroups.Count)" "INFO"
}
else {
    Write-Log "Sicherheitsgruppen-CSV nicht gefunden. Werde Sicherheitsgruppen direkt von Servern lesen..." "WARNING"
}

# Funktion zum Extrahieren der OU aus DistinguishedName
function Get-OUFromDN {
    param([string]$DistinguishedName)
    
    if (-not $DistinguishedName) {
        return ""
    }
    
    # Entferne den CN-Teil und behalte nur die OU-Struktur
    $dnParts = $DistinguishedName -split ','
    $ouParts = @()
    foreach ($part in $dnParts) {
        if ($part -match '^OU=') {
            $ouParts += $part
        }
    }
    if ($ouParts.Count -gt 0) {
        return $ouParts -join ','
    }
    return ""
}

# Funktion zum Extrahieren des Standorts aus OU
function Get-LocationFromOU {
    param([string]$OU)
    
    if (-not $OU -or $OU.Trim() -eq "") {
        return ""
    }
    
    # Typische Standort-OU-Patterns
    $locationPatterns = @(
        'OU=Standorte',
        'OU=Standort',
        'OU=Locations',
        'OU=Location',
        'OU=StÃ¤dte',
        'OU=Stadt'
    )
    
    $dnParts = $OU -split ','
    $location = ""
    
    # Suche nach Standort-OU
    foreach ($part in $dnParts) {
        foreach ($pattern in $locationPatterns) {
            if ($part -match "^$pattern") {
                # NÃ¤chste OU nach Standort ist der eigentliche Standort
                $index = [array]::IndexOf($dnParts, $part)
                if ($index -gt 0) {
                    $locationPart = $dnParts[$index - 1]
                    if ($locationPart -match '^OU=(.+)') {
                        $location = $matches[1]
                        break
                    }
                }
            }
        }
        if ($location) { break }
    }
    
    # Falls kein Standort-Pattern gefunden, nimm die erste OU als Standort
    if (-not $location -and $dnParts.Count -gt 0) {
        $firstOU = $dnParts[0]
        if ($firstOU -match '^OU=(.+)') {
            $location = $matches[1]
        }
    }
    
    return $location
}

# Funktion zum Ermitteln der hÃ¤ufigsten Werte aus einem Array
function Get-MostCommonValue {
    param(
        [array]$Values
    )
    
    if ($Values.Count -eq 0) {
        return @{
            Value = ""
            Count = 0
            AllValues = @()
        }
    }
    
    $valueCount = @{}
    foreach ($val in $Values) {
        if ($val -and $val.Trim() -ne "") {
            $normalized = $val.Trim()
            if (-not $valueCount.ContainsKey($normalized)) {
                $valueCount[$normalized] = 0
            }
            $valueCount[$normalized]++
        }
    }
    
    # Finde hÃ¤ufigsten Wert
    $mostCommon = ""
    $maxCount = 0
    foreach ($val in $valueCount.Keys) {
        if ($valueCount[$val] -gt $maxCount) {
            $maxCount = $valueCount[$val]
            $mostCommon = $val
        }
    }
    
    # Alle eindeutigen Werte
    $allUnique = $valueCount.Keys | Sort-Object
    
    return @{
        Value = $mostCommon
        Count = $maxCount
        AllValues = $allUnique
    }
}

# Funktion zum Ermitteln der hÃ¤ufigsten Adresse und Abteilung
function Get-MostCommonAddress {
    param(
        [array]$Addresses,
        [array]$Departments
    )
    
    # ZÃ¤hle Adressen
    $addressCount = @{}
    foreach ($addr in $Addresses) {
        if ($addr -and $addr.Trim() -ne "") {
            $normalized = $addr.Trim()
            if (-not $addressCount.ContainsKey($normalized)) {
                $addressCount[$normalized] = 0
            }
            $addressCount[$normalized]++
        }
    }
    
    # ZÃ¤hle Abteilungen
    $deptCount = @{}
    foreach ($dept in $Departments) {
        if ($dept -and $dept.Trim() -ne "") {
            $normalized = $dept.Trim()
            if (-not $deptCount.ContainsKey($normalized)) {
                $deptCount[$normalized] = 0
            }
            $deptCount[$normalized]++
        }
    }
    
    # Finde hÃ¤ufigste Adresse
    $mostCommonAddress = ""
    $maxAddressCount = 0
    foreach ($addr in $addressCount.Keys) {
        if ($addressCount[$addr] -gt $maxAddressCount) {
            $maxAddressCount = $addressCount[$addr]
            $mostCommonAddress = $addr
        }
    }
    
    # Finde hÃ¤ufigste Abteilung
    $mostCommonDepartment = ""
    $maxDeptCount = 0
    foreach ($dept in $deptCount.Keys) {
        if ($deptCount[$dept] -gt $maxDeptCount) {
            $maxDeptCount = $deptCount[$dept]
            $mostCommonDepartment = $dept
        }
    }
    
    return @{
        StreetAddress = $mostCommonAddress
        Department = $mostCommonDepartment
        AddressCount = $maxAddressCount
        DepartmentCount = $maxDeptCount
        TotalMembers = $Addresses.Count
    }
}

# Funktion zur KonsistenzprÃ¼fung
function Test-Consistency {
    param(
        [string]$GroupOU,
        [array]$AllGroupOUs,
        [string]$UserOU,
        [string]$StreetAddress,
        [string]$Department,
        [int]$TotalMembers
    )
    
    $status = "Konsistent"
    $reasons = @()
    
    # PrÃ¼fe OU-Konsistenz: Gruppen-OU vs. Benutzer-OU
    if ($GroupOU -and $UserOU) {
        # Extrahiere oberste OU fÃ¼r Vergleich
        $groupTopOU = ""
        $userTopOU = ""
        
        if ($GroupOU -match '^OU=([^,]+)') {
            $groupTopOU = $matches[1]
        }
        if ($UserOU -match '^OU=([^,]+)') {
            $userTopOU = $matches[1]
        }
        
        if ($groupTopOU -ne $userTopOU -and $groupTopOU -ne "" -and $userTopOU -ne "") {
            $status = "Inkonsistent"
            $reasons += "Gruppen-OU ($groupTopOU) stimmt nicht mit Benutzer-OU ($userTopOU) Ã¼berein"
        }
    }
    
    # PrÃ¼fe ob mehrere verschiedene Gruppen-OUs vorhanden sind
    if ($AllGroupOUs.Count -gt 1) {
        $uniqueOUs = $AllGroupOUs | Select-Object -Unique
        if ($uniqueOUs.Count -gt 1) {
            $status = "Inkonsistent"
            $reasons += "Mehrere verschiedene Gruppen-OUs gefunden"
        }
    }
    
    # PrÃ¼fe ob keine Daten vorhanden
    if ($TotalMembers -eq 0) {
        $status = "UnvollstÃ¤ndig"
        $reasons += "Keine Benutzerdaten verfÃ¼gbar"
    }
    
    # PrÃ¼fe ob Adresse fehlt
    if (-not $StreetAddress -or $StreetAddress.Trim() -eq "") {
        if ($status -eq "Konsistent") {
            $status = "UnvollstÃ¤ndig"
        }
        $reasons += "Keine Adresse ermittelt"
    }
    
    # PrÃ¼fe ob Abteilung fehlt
    if (-not $Department -or $Department.Trim() -eq "") {
        if ($status -eq "Konsistent") {
            $status = "UnvollstÃ¤ndig"
        }
        $reasons += "Keine Abteilung ermittelt"
    }
    
    return @{
        Status = $status
        Reason = if ($reasons.Count -gt 0) { ($reasons -join "; ") } else { "" }
    }
}

# Funktion zum Abrufen der Sicherheitsgruppen und einzelnen Benutzer eines Druckers
function Get-PrinterSecurityGroups {
    param(
        [string]$Server,
        [string]$PrinterName
    )
    
    $key = "$Server|$PrinterName"
    
    # PrÃ¼fe ob bereits in Mapping vorhanden
    if ($securityGroupMapping.ContainsKey($key)) {
        return $securityGroupMapping[$key]
    }
    
    # Versuche direkt vom Server zu lesen
    $groups = @()
    try {
        if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) {
            Write-Log "  Server $Server ist nicht erreichbar" "WARNING"
            return $groups
        }
        
        $scriptBlock = {
            param($PrinterName)
            
            try {
                $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
                if (-not $printer) {
                    return @()
                }
                
                $wmiPrinter = Get-WmiObject -Class Win32_Printer -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                if (-not $wmiPrinter) {
                    return @()
                }
                
                $sd = $wmiPrinter.GetSecurityDescriptor()
                if ($sd.ReturnValue -ne 0) {
                    return @()
                }
                
                $dacl = $sd.Descriptor.DACL
                $groupNames = @()
                
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
                    
                    # Ãœberspringe System-Accounts und Admin-Accounts
                    if (Test-IsSystemOrAdminAccount -AccountName $fullName) {
                        continue
                    }
                    
                        $groupName = $identity
                        if ($fullName -match "\\") {
                            $groupName = $fullName.Split('\')[-1]
                        }
                        $groupNames += $groupName
                }
                
                return $groupNames
            }
            catch {
                return @()
            }
        }
        
        $groups = Invoke-Command -ComputerName $Server -ScriptBlock $scriptBlock -ArgumentList $PrinterName -ErrorAction SilentlyContinue
        
        if ($groups) {
            $securityGroupMapping[$key] = $groups
        }
    }
    catch {
        Write-Log "  Fehler beim Abrufen der Sicherheitsgruppen: $($_.Exception.Message)" "WARNING"
    }
    
    return $groups
}

# Funktion zum PrÃ¼fen, ob ein Name eine Gruppe oder ein Benutzer ist
function Test-IsGroup {
    param([string]$Name)
    
    if (-not $Name -or $Name.Trim() -eq "") {
        return $false
    }
    
    try {
        $group = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
        if (-not $group) {
            $group = Get-ADGroup -Filter "SamAccountName -eq '$Name'" -ErrorAction SilentlyContinue
        }
        return ($null -ne $group)
    }
    catch {
        return $false
    }
}

# Funktion zum PrÃ¼fen, ob ein Account ein System-Account oder Admin-Account ist (sollte Ã¼bersprungen werden)
function Test-IsSystemOrAdminAccount {
    param([string]$AccountName)
    
    if (-not $AccountName -or $AccountName.Trim() -eq "") {
        return $false
    }
    
    $accountNameUpper = $AccountName.ToUpper()
    
    # PrÃ¼fe auf bekannte System-Accounts
    $systemAccounts = @(
        "JEDER", "EVERYONE", "JEDE",
        "CREATOR OWNER", "ERSTELLER-BESITZER", "CREATOR-OWNER",
        "NT AUTHORITY\SYSTEM", "NT-AUTORITÃ„T\SYSTEM",
        "BUILTIN\ADMINISTRATORS", "VORDEFINIERT\ADMINISTRATOREN",
        "ALL APPLICATION PACKAGES", "ALLE ANWENDUNGSPAKETE",
        "ANONYMOUS LOGON", "ANONYME ANMELDUNG",
        "AUTHENTICATED USERS", "AUTHENTIFIZIERTE BENUTZER"
    )
    
    foreach ($sysAccount in $systemAccounts) {
        if ($accountNameUpper -like "*$sysAccount*") {
            return $true
        }
    }
    
    # PrÃ¼fe ob es ein Benutzer oder eine Gruppe in AD ist
    try {
        # PrÃ¼fe zuerst ob es eine Gruppe ist
        $group = Get-ADGroup -Filter "Name -eq '$AccountName'" -ErrorAction SilentlyContinue
        if (-not $group) {
            $group = Get-ADGroup -Filter "SamAccountName -eq '$AccountName'" -ErrorAction SilentlyContinue
        }
        
        if ($group) {
            # PrÃ¼fe ob es eine Admin-Gruppe ist
            $adminGroups = @(
                "Domain Admins", "DOMAIN ADMINS",
                "Enterprise Admins", "ENTERPRISE ADMINS",
                "Schema Admins", "SCHEMA ADMINS",
                "Administrators", "ADMINISTRATORS",
                "Administratoren", "ADMINISTRATOREN",
                "BUILTIN\Administrators", "VORDEFINIERT\Administratoren"
            )
            
            foreach ($adminGroup in $adminGroups) {
                if ($group.Name -eq $adminGroup -or $group.SamAccountName -eq $adminGroup -or 
                    $group.DistinguishedName -like "*$adminGroup*") {
                    return $true
                }
            }
            
            # PrÃ¼fe Gruppenmitgliedschaften rekursiv
            $groupMemberships = Get-ADPrincipalGroupMembership -Identity $group.DistinguishedName -ErrorAction SilentlyContinue
            if ($groupMemberships) {
                foreach ($membership in $groupMemberships) {
                    foreach ($adminGroup in $adminGroups) {
                        if ($membership.Name -eq $adminGroup -or $membership.SamAccountName -eq $adminGroup) {
                            return $true
                        }
                    }
                }
            }
            
            return $false  # Es ist eine Gruppe, aber keine Admin-Gruppe
        }
        
        # PrÃ¼fe ob es ein Benutzer ist
        $user = Get-ADUser -Filter "SamAccountName -eq '$AccountName'" -ErrorAction SilentlyContinue
        if (-not $user) {
            $user = Get-ADUser -Filter "Name -eq '$AccountName'" -ErrorAction SilentlyContinue
        }
        
        if ($user) {
            # PrÃ¼fe ob Benutzer Mitglied von Admin-Gruppen ist
            $adminGroups = @(
                "Domain Admins", "DOMAIN ADMINS",
                "Enterprise Admins", "ENTERPRISE ADMINS",
                "Schema Admins", "SCHEMA ADMINS",
                "Administrators", "ADMINISTRATORS",
                "Administratoren", "ADMINISTRATOREN"
            )
            
            $userGroups = Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName -ErrorAction SilentlyContinue
            if ($userGroups) {
                foreach ($group in $userGroups) {
                    foreach ($adminGroup in $adminGroups) {
                        if ($group.Name -eq $adminGroup -or $group.SamAccountName -eq $adminGroup) {
                            return $true
                        }
                    }
                }
            }
            
            # PrÃ¼fe ob Account-Name auf Admin hinweist (z.B. "abs", "mha", etc. - wenn sie Admin-Rechte haben)
            # Dies ist eine Fallback-PrÃ¼fung fÃ¼r Accounts, die nicht in Standard-Admin-Gruppen sind
            # aber trotzdem Admin-Rechte haben kÃ¶nnten
            $adminPatterns = @("ADMIN", "ADMINISTRATOR")
            foreach ($pattern in $adminPatterns) {
                if ($accountNameUpper -like "*$pattern*") {
                    return $true
                }
            }
            
            return $false  # Es ist ein Benutzer, aber kein Admin
        }
        
        # Wenn weder Gruppe noch Benutzer gefunden wurde, kÃ¶nnte es ein System-Account sein
        # PrÃ¼fe auf typische System-Account-Namen
        if ($accountNameUpper -in @("ADMINISTRATOR", "ADMIN", "SYSTEM", "SERVICE")) {
            return $true
        }
        
        return $false
    }
    catch {
        # Bei Fehler: Wenn der Name verdÃ¤chtig aussieht, lieber Ã¼berspringen
        if ($accountNameUpper -in @("ADMINISTRATOR", "ADMIN", "SYSTEM", "SERVICE", "ABS", "MHA")) {
            return $true
        }
        return $false
    }
}

# Funktion zum PrÃ¼fen, ob ein Benutzer Mitglied der DomÃ¤nen-Admins-Gruppe ist
function Test-IsDomainAdmin {
    param([string]$UserName)
    
    if (-not $UserName -or $UserName.Trim() -eq "") {
        return $false
    }
    
    try {
        # Finde Benutzer
        $user = Get-ADUser -Filter "SamAccountName -eq '$UserName'" -ErrorAction SilentlyContinue
        if (-not $user) {
            $user = Get-ADUser -Filter "Name -eq '$UserName'" -ErrorAction SilentlyContinue
        }
        
        if (-not $user) {
            return $false
        }
        
        # PrÃ¼fe ob Benutzer Mitglied der DomÃ¤nen-Admins-Gruppe ist
        $domainAdmins = Get-ADGroup -Identity "Domain Admins" -ErrorAction SilentlyContinue
        if ($domainAdmins) {
            $members = Get-ADGroupMember -Identity $domainAdmins.DistinguishedName -ErrorAction SilentlyContinue
            foreach ($member in $members) {
                if ($member.DistinguishedName -eq $user.DistinguishedName) {
                    return $true
                }
            }
        }
        
        # PrÃ¼fe auch Ã¼ber Gruppenmitgliedschaften des Benutzers
        $userGroups = Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName -ErrorAction SilentlyContinue
        if ($userGroups) {
            foreach ($group in $userGroups) {
                if ($group.Name -eq "Domain Admins" -or $group.SamAccountName -eq "Domain Admins") {
                    return $true
                }
            }
        }
        
        return $false
    }
    catch {
        Write-Log "    Fehler beim PrÃ¼fen auf DomÃ¤nen-Admin fÃ¼r $UserName : $($_.Exception.Message)" "WARNING"
        return $false
    }
}

# Funktion zum Verarbeiten einzelner Benutzer (wenn keine Gruppen gefunden wurden)
function Get-UserData {
    param([string]$UserName)
    
    try {
        $user = Get-ADUser -Filter "SamAccountName -eq '$UserName'" -Properties StreetAddress, Department -ErrorAction SilentlyContinue
        if (-not $user) {
            $user = Get-ADUser -Filter "Name -eq '$UserName'" -Properties StreetAddress, Department -ErrorAction SilentlyContinue
        }
        
        if ($user) {
            $userOU = Get-OUFromDN -DistinguishedName $user.DistinguishedName
            return @{
                StreetAddress = if ($user.StreetAddress) { $user.StreetAddress } else { "" }
                Department = if ($user.Department) { $user.Department } else { "" }
                UserOU = $userOU
                Found = $true
            }
        }
    }
    catch {
        Write-Log "    Fehler beim Abrufen der Benutzerdaten fÃ¼r $UserName : $($_.Exception.Message)" "WARNING"
    }
    
    return @{
        StreetAddress = ""
        Department = ""
        UserOU = ""
        Found = $false
    }
}

# Funktion zum Erkennen von SafeQ-Druckern
function Test-IsSafeQPrinter {
    param(
        [string]$PrinterName,
        [string]$PortName
    )
    
    # PrÃ¼fe Druckername
    if ($PrinterName -like "*SafeQ*" -or $PrinterName -like "*Follow me*") {
        return $true
    }
    
    # PrÃ¼fe Port (SafeQ-Drucker haben mehrere Ports: SafeQ1,SafeQ2,SafeQ3)
    if ($PortName -like "*SafeQ1*" -or $PortName -like "*SafeQ2*" -or $PortName -like "*SafeQ3*") {
        return $true
    }
    
    return $false
}

# Verarbeite jeden Drucker
$results = @()
$processedGroups = @{}  # Cache fÃ¼r bereits verarbeitete Gruppen

foreach ($printer in $printers) {
    $server = $printer.Server
    $printerName = $printer.PrinterName
    
    # Ãœberspringe virtuelle Drucker
    if ($printerName -like "Microsoft*" -or $printerName -like "*XPS*" -or $printerName -like "*PDF*") {
        continue
    }
    
    # PrÃ¼fe ob SafeQ-Drucker
    $isSafeQ = Test-IsSafeQPrinter -PrinterName $printerName -PortName $printer.PortName
    
    if ($isSafeQ) {
        Write-Log "Verarbeite SafeQ-Drucker: $printerName auf $server" "INFO"
    } else {
        Write-Log "Verarbeite Drucker: $printerName auf $server" "INFO"
    }
    
    # Hole Sicherheitsgruppen
    $securityGroups = Get-PrinterSecurityGroups -Server $server -PrinterName $printerName
    
    # PrÃ¼fe ob einzelne Benutzer vorhanden sind (wenn keine Gruppen gefunden wurden)
    $individualUsers = @()
    $hasGroups = $false
    
    if ($securityGroups.Count -eq 0) {
        Write-Log "  Keine Sicherheitsgruppen gefunden - prÃ¼fe auf einzelne Benutzer" "WARNING"
        
        # Versuche direkt vom Server die einzelnen Benutzer zu lesen
        try {
            if (Test-Connection -ComputerName $server -Count 1 -Quiet) {
                $scriptBlock = {
                    param($PrinterName)
                    
                    try {
                        $wmiPrinter = Get-WmiObject -Class Win32_Printer -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
                        if (-not $wmiPrinter) {
                            return @()
                        }
                        
                        $sd = $wmiPrinter.GetSecurityDescriptor()
                        if ($sd.ReturnValue -ne 0) {
                            return @()
                        }
                        
                        $dacl = $sd.Descriptor.DACL
                        $userNames = @()
                        
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
                            
                            # Ãœberspringe System-Accounts und Admin-Accounts
                            if (Test-IsSystemOrAdminAccount -AccountName $fullName) {
                                continue
                            }
                            
                                $userName = $identity
                                if ($fullName -match "\\") {
                                    $userName = $fullName.Split('\')[-1]
                                }
                                $userNames += $userName
                        }
                        
                        return $userNames
                    }
                    catch {
                        return @()
                    }
                }
                
                $allIdentities = Invoke-Command -ComputerName $server -ScriptBlock $scriptBlock -ArgumentList $printerName -ErrorAction SilentlyContinue
                
                if ($allIdentities) {
                    # PrÃ¼fe welche IdentitÃ¤ten Gruppen und welche Benutzer sind
                    foreach ($identity in $allIdentities) {
                        if (Test-IsGroup -Name $identity) {
                            $securityGroups += $identity
                            $hasGroups = $true
                        }
                        else {
                            $individualUsers += $identity
                        }
                    }
                }
            }
        }
        catch {
            Write-Log "  Fehler beim Abrufen der einzelnen Benutzer: $($_.Exception.Message)" "WARNING"
        }
    }
    else {
        $hasGroups = $true
    }
    
    # Wenn weder Gruppen noch einzelne Benutzer gefunden wurden
    if ($securityGroups.Count -eq 0 -and $individualUsers.Count -eq 0) {
        Write-Log "  Keine Sicherheitsgruppen oder einzelnen Benutzer gefunden" "WARNING"
        # PrÃ¼fe ob SafeQ-Drucker
        $isSafeQ = Test-IsSafeQPrinter -PrinterName $printerName -PortName $printer.PortName
        
        $results += [PSCustomObject]@{
            Server = $server
            PrinterName = $printerName
            ShareName = $printer.ShareName
            Location = $printer.Location
            PortAddress = $printer.PortAddress
            IsSafeQ = $isSafeQ  # Kennzeichnung fÃ¼r SafeQ-Drucker
            SecurityGroups = ""
            SecurityGroupOU = ""
            SecurityGroupOU_MostCommon = ""
            UserOU = ""
            LocationFromOU = ""
            StreetAddress = ""
            Department = ""
            AddressCount = 0
            DepartmentCount = 0
            TotalMembers = 0
            ConsistencyStatus = "UnvollstÃ¤ndig"
            ConsistencyReason = "Keine Gruppen oder Benutzer gefunden"
            Status = "Keine Gruppen oder Benutzer gefunden"
        }
        continue
    }
    
    if ($hasGroups) {
        Write-Log "  Gefundene Sicherheitsgruppen: $($securityGroups.Count)" "INFO"
    }
    else {
        Write-Log "  Keine Sicherheitsgruppen gefunden, aber einzelne Benutzer: $($individualUsers.Count)" "INFO"
    }
    
    # Sammle alle Adressen und Abteilungen der Gruppenmitglieder ODER einzelnen Benutzer
    $allAddresses = @()
    $allDepartments = @()
    $allGroupOUs = @()  # Sammle OUs der Sicherheitsgruppen
    $allUserOUs = @()  # Sammle OUs der Benutzer
    $groupDetails = @()
    
    # Verarbeite Sicherheitsgruppen (falls vorhanden)
    foreach ($groupName in $securityGroups) {
        try {
            # Ãœberspringe System-Accounts und Admin-Accounts, die fÃ¤lschlicherweise als Gruppen erkannt wurden
            if (Test-IsSystemOrAdminAccount -AccountName $groupName) {
                Write-Log "    Gruppe $groupName wird Ã¼bersprungen (System- oder Admin-Account, keine echte Gruppe)" "INFO"
                continue
            }
            
            # PrÃ¼fe Cache
            if ($processedGroups.ContainsKey($groupName)) {
                $groupData = $processedGroups[$groupName]
                $allAddresses += $groupData.Addresses
                $allDepartments += $groupData.Departments
                if ($groupData.OU) {
                    $allGroupOUs += $groupData.OU
                }
                if ($groupData.UserOUs) {
                    $allUserOUs += $groupData.UserOUs
                }
                $groupDetails += $groupData
                continue
            }
            
            # Finde Gruppe in AD
            $groupInfo = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
            if (-not $groupInfo) {
                $groupInfo = Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction SilentlyContinue
            }
            
            if (-not $groupInfo) {
                Write-Log "    Gruppe nicht gefunden: $groupName" "WARNING"
                continue
            }
            
            # Extrahiere OU aus DistinguishedName
            $groupOU = Get-OUFromDN -DistinguishedName $groupInfo.DistinguishedName
            
            # Hole Mitglieder
            $members = Get-ADGroupMember -Identity $groupInfo.DistinguishedName -ErrorAction SilentlyContinue
            Write-Log "    Gruppe $groupName : $($members.Count) Mitglieder, OU: $groupOU" "INFO"
            
            $groupAddresses = @()
            $groupDepartments = @()
            $groupUserOUs = @()  # Sammle OUs der Benutzer
            
            foreach ($member in $members) {
                if ($member.ObjectClass -eq "user") {
                    try {
                        $user = Get-ADUser -Identity $member.DistinguishedName -Properties StreetAddress, Department -ErrorAction SilentlyContinue
                        if ($user) {
                            if ($user.StreetAddress) {
                                $groupAddresses += $user.StreetAddress
                            }
                            if ($user.Department) {
                                $groupDepartments += $user.Department
                            }
                            # Extrahiere OU des Benutzers
                            $userOU = Get-OUFromDN -DistinguishedName $user.DistinguishedName
                            if ($userOU) {
                                $groupUserOUs += $userOU
                            }
                        }
                    }
                    catch {
                        # Ignoriere Fehler bei einzelnen Benutzern
                    }
                }
            }
            
            # Speichere im Cache
            $groupData = @{
                GroupName = $groupName
                Addresses = $groupAddresses
                Departments = $groupDepartments
                OU = $groupOU
                UserOUs = $groupUserOUs
                MemberCount = $members.Count
            }
            $processedGroups[$groupName] = $groupData
            
            $allAddresses += $groupAddresses
            $allDepartments += $groupDepartments
            if ($groupOU) {
                $allGroupOUs += $groupOU
            }
            $groupDetails += $groupData
        }
        catch {
            Write-Log "    Fehler beim Verarbeiten der Gruppe $groupName : $($_.Exception.Message)" "WARNING"
        }
    }
    
    # Verarbeite einzelne Benutzer (falls keine Gruppen gefunden wurden)
    if (-not $hasGroups -and $individualUsers.Count -gt 0) {
        Write-Log "  Verarbeite einzelne Benutzer..." "INFO"
        foreach ($userName in $individualUsers) {
            try {
                # Ãœberspringe System-Accounts und Admin-Accounts
                if (Test-IsSystemOrAdminAccount -AccountName $userName) {
                    Write-Log "    Account $userName wird Ã¼bersprungen (System- oder Admin-Account)" "INFO"
                    continue
                }
                
                # PrÃ¼fe ob Benutzer DomÃ¤nen-Admin ist - diese werden Ã¼bersprungen (zusÃ¤tzliche PrÃ¼fung)
                if (Test-IsDomainAdmin -UserName $userName) {
                    Write-Log "    Benutzer $userName ist DomÃ¤nen-Admin und wird Ã¼bersprungen (hat Zugriff auf alle Drucker)" "INFO"
                    continue
                }
                
                $userData = Get-UserData -UserName $userName
                if ($userData.Found) {
                    if ($userData.StreetAddress) {
                        $allAddresses += $userData.StreetAddress
                    }
                    if ($userData.Department) {
                        $allDepartments += $userData.Department
                    }
                    if ($userData.UserOU) {
                        $allUserOUs += $userData.UserOU
                    }
                    Write-Log "    Benutzer $userName : Adresse='$($userData.StreetAddress)', Abteilung='$($userData.Department)', OU='$($userData.UserOU)'" "INFO"
                }
                else {
                    Write-Log "    Benutzer nicht gefunden: $userName" "WARNING"
                }
            }
            catch {
                Write-Log "    Fehler beim Verarbeiten des Benutzers $userName : $($_.Exception.Message)" "WARNING"
            }
        }
    }
    
    # Ermittle hÃ¤ufigste Adresse und Abteilung
    $mostCommon = Get-MostCommonAddress -Addresses $allAddresses -Departments $allDepartments
    
    # Ermittle alle OUs der Sicherheitsgruppen (Punkt 2: Alle OUs als Liste)
    $groupOUResult = Get-MostCommonValue -Values $allGroupOUs
    $allGroupOUsList = if ($groupOUResult.AllValues.Count -gt 0) { ($groupOUResult.AllValues -join "; ") } else { "" }
    $mostCommonGroupOU = $groupOUResult.Value
    
    # Ermittle hÃ¤ufigste OU der Benutzer (Punkt 4: OU der Benutzer erfassen)
    $userOUResult = Get-MostCommonValue -Values $allUserOUs
    $mostCommonUserOU = $userOUResult.Value
    
    # Extrahiere Standort aus OU (Punkt 5: Standort-Information)
    # Wenn keine Gruppen-OU vorhanden, verwende Benutzer-OU
    $ouForLocation = if ($mostCommonGroupOU) { $mostCommonGroupOU } else { $mostCommonUserOU }
    $locationFromOU = Get-LocationFromOU -OU $ouForLocation
    
    # KonsistenzprÃ¼fung (Punkt 3: Automatische KonsistenzprÃ¼fung)
    $consistency = Test-Consistency -GroupOU $mostCommonGroupOU -AllGroupOUs $allGroupOUs -UserOU $mostCommonUserOU -StreetAddress $mostCommon.StreetAddress -Department $mostCommon.Department -TotalMembers $mostCommon.TotalMembers
    
    Write-Log "  Ergebnis: Adresse='$($mostCommon.StreetAddress)' ($($mostCommon.AddressCount)/$($mostCommon.TotalMembers)), Abteilung='$($mostCommon.Department)' ($($mostCommon.DepartmentCount)/$($mostCommon.TotalMembers)), Gruppen-OU='$mostCommonGroupOU', Benutzer-OU='$mostCommonUserOU', Standort='$locationFromOU', Status='$($consistency.Status)'" "INFO"
    
    if ($isSafeQ) {
        Write-Log "  SafeQ-Drucker erkannt - 'SafeQ' wird bei Druckerbennung angehÃ¤ngt" "INFO"
    }
    
    # Erstelle SecurityGroups-String (Gruppen oder einzelne Benutzer)
    $securityGroupsString = ""
    if ($hasGroups) {
        $securityGroupsString = ($securityGroups -join "; ")
    }
    elseif ($individualUsers.Count -gt 0) {
        $securityGroupsString = "Einzelne Benutzer: " + ($individualUsers -join "; ")
    }
    
    $results += [PSCustomObject]@{
        Server = $server
        PrinterName = $printerName
        ShareName = $printer.ShareName
        Location = $printer.Location
        PortAddress = $printer.PortAddress
        IsSafeQ = $isSafeQ  # Kennzeichnung fÃ¼r SafeQ-Drucker
        SecurityGroups = $securityGroupsString
        SecurityGroupOU = $allGroupOUsList  # Alle OUs als Liste
        SecurityGroupOU_MostCommon = $mostCommonGroupOU  # HÃ¤ufigste OU
        UserOU = $mostCommonUserOU  # OU der Benutzer
        LocationFromOU = $locationFromOU  # Standort aus OU
        StreetAddress = $mostCommon.StreetAddress
        Department = $mostCommon.Department
        AddressCount = $mostCommon.AddressCount
        DepartmentCount = $mostCommon.DepartmentCount
        TotalMembers = $mostCommon.TotalMembers
        ConsistencyStatus = $consistency.Status
        ConsistencyReason = $consistency.Reason
        Status = if ($hasGroups) { "OK" } else { "OK (Einzelne Benutzer)" }
    }
}

# Exportiere Ergebnisse
if ($results.Count -gt 0) {
    $csvFile = Join-Path $OutputDir "3.1-Drucker-Adressen.csv"
    $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Mapping-Datei erstellt: $csvFile" "SUCCESS"
    
    Write-Host ""
    Write-Host "=== Zusammenfassung ===" -ForegroundColor Green
    Write-Host "Verarbeitete Drucker: $($results.Count)" -ForegroundColor Green
    
    $withAddress = ($results | Where-Object { $_.StreetAddress -ne "" }).Count
    $withDepartment = ($results | Where-Object { $_.Department -ne "" }).Count
    $withGroupOU = ($results | Where-Object { $_.SecurityGroupOU -ne "" }).Count
    $withUserOU = ($results | Where-Object { $_.UserOU -ne "" }).Count
    $withLocation = ($results | Where-Object { $_.LocationFromOU -ne "" }).Count
    
    $safeQCount = ($results | Where-Object { $_.IsSafeQ -eq $true }).Count
    
    Write-Host "Drucker mit Adresse: $withAddress" -ForegroundColor Green
    Write-Host "Drucker mit Abteilung: $withDepartment" -ForegroundColor Green
    Write-Host "Drucker mit Gruppen-OU: $withGroupOU" -ForegroundColor Green
    Write-Host "Drucker mit Benutzer-OU: $withUserOU" -ForegroundColor Green
    Write-Host "Drucker mit Standort: $withLocation" -ForegroundColor Green
    Write-Host "SafeQ-Drucker: $safeQCount" -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "=== Konsistenz-Status ===" -ForegroundColor Cyan
    $consistent = ($results | Where-Object { $_.ConsistencyStatus -eq "Konsistent" }).Count
    $inconsistent = ($results | Where-Object { $_.ConsistencyStatus -eq "Inkonsistent" }).Count
    $incomplete = ($results | Where-Object { $_.ConsistencyStatus -eq "UnvollstÃ¤ndig" }).Count
    Write-Host "Konsistent: $consistent" -ForegroundColor Green
    Write-Host "Inkonsistent: $inconsistent" -ForegroundColor Yellow
    Write-Host "UnvollstÃ¤ndig: $incomplete" -ForegroundColor Red
    
    Write-Host ""
    Write-Host "=== Inkonsistente Drucker ===" -ForegroundColor Yellow
    $inconsistentPrinters = $results | Where-Object { $_.ConsistencyStatus -eq "Inkonsistent" }
    if ($inconsistentPrinters.Count -gt 0) {
        foreach ($printer in $inconsistentPrinters) {
            Write-Host "  - $($printer.PrinterName) auf $($printer.Server)" -ForegroundColor Cyan
            Write-Host "    Grund: $($printer.ConsistencyReason)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Keine inkonsistenten Drucker gefunden" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== Drucker ohne Adresse ===" -ForegroundColor Yellow
    $withoutAddress = $results | Where-Object { $_.StreetAddress -eq "" }
    if ($withoutAddress.Count -gt 0) {
        foreach ($printer in $withoutAddress) {
            Write-Host "  - $($printer.PrinterName) auf $($printer.Server)" -ForegroundColor Cyan
            Write-Host "    Gruppen: $($printer.SecurityGroups)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Alle Drucker haben Adressen" -ForegroundColor Green
    }
}
else {
    Write-Host "KEINE Ergebnisse gefunden!" -ForegroundColor Yellow
    Write-Log "KEINE Ergebnisse gefunden" "INFO"
    
    # Erstelle leere CSV-Datei trotzdem
    $csvFile = Join-Path $OutputDir "3.1-Drucker-Adressen.csv"
    $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Leere CSV-Datei erstellt: $csvFile" "INFO"
}

Write-Host ""
Write-Host "Export-Datei: $(Join-Path $OutputDir '3.1-Drucker-Adressen.csv')" -ForegroundColor Cyan

Write-Log "=== Analyse Drucker-Adressen abgeschlossen ===" "INFO"

