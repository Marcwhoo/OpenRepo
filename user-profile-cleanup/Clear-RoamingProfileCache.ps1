# ==================================================================
# Roaming-Profile Cleanup - Robust mit mehr Logging 2025
# Nur aktuell angemeldeter Benutzer, ausser <SERVICE-ACCOUNT>
# AD: Exakter Profilpfad aus Active Directory
# ==================================================================

param(
    [switch]$DryRun = $false
)

$debugLog = "$env:TEMP\UserProfile-cleaner-debug.log"

try {
    "=== Script gestartet: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $debugLog -Append -Encoding UTF8
    "Parameter DryRun: $DryRun" | Out-File -FilePath $debugLog -Append -Encoding UTF8
}
catch {
    # Ignoriere Fehler
}

$ErrorActionPreference = "Continue"

$ServerRoot = "\\<DOMAIN-FQDN>\<SHARE>"
$ADBaseDN = "DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
$ExcludedUsers = @("<SERVICE-ACCOUNT>")  # Add service/admin accounts to exclude

$AdditionalProfileRoots = @(
    "$ServerRoot\<PROFILE-FOLDER>"
)

# Log-Verzeichnis direkt setzen - verwende script: Scope um Scope-Probleme zu vermeiden
$script:HomeLogRoot = "\\<FILESERVER>\<SHARE>\<HOMEDRIVE-ROOT>\<YOUR-USERNAME>"
$script:LogDir = $script:HomeLogRoot + "\Scriptlogs\Userprofile_cleaner"

Write-Host "Pruefe Netzwerk-Verzeichnis: $($script:LogDir)" -ForegroundColor Cyan

$errorOccurred = $false
$errorMessage = ""

try {
    Write-Host "Pruefe Root-Verzeichnis: $($script:HomeLogRoot)" -ForegroundColor Yellow
    $rootTest = $null
    $job = Start-Job -ScriptBlock { param($path) Test-Path $path -ErrorAction Stop } -ArgumentList $script:HomeLogRoot
    
    if (Wait-Job $job -Timeout 10) {
        $rootTest = Receive-Job $job
        Remove-Job $job
    }
    else {
        Remove-Job $job -Force
        throw "Timeout beim Pruefen des Root-Verzeichnisses (mehr als 10 Sekunden)."
    }
    
    if (-not $rootTest) {
        throw "Root-Verzeichnis ist nicht erreichbar. Bitte Netzwerkverbindung pruefen."
    }
    
    Write-Host "Root-Verzeichnis erreichbar." -ForegroundColor Green
    
    Write-Host "Pruefe Log-Verzeichnis: $($script:LogDir)" -ForegroundColor Yellow
    $logTest = Test-Path $script:LogDir -ErrorAction SilentlyContinue
    
    if ($logTest) {
        Write-Host "Log-Verzeichnis existiert bereits: $($script:LogDir)" -ForegroundColor Green
    }
    else {
        Write-Host "Erstelle Log-Verzeichnis: $($script:LogDir)" -ForegroundColor Yellow
        $null = New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction Stop
        Write-Host "Log-Verzeichnis erstellt: $($script:LogDir)" -ForegroundColor Green
    }
}
catch {
    $errorOccurred = $true
    $errorMessage = $_.Exception.Message
    Write-Host "" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "FEHLER: Netzwerk-Log-Verzeichnis nicht erreichbar!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Pfad: $($script:LogDir)" -ForegroundColor Red
    Write-Host "Fehler: $errorMessage" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
}

if ($errorOccurred) {
    try {
        "FEHLER beim Initialisieren des Log-Verzeichnisses: $errorMessage" | Out-File -FilePath $debugLog -Append -Encoding UTF8
        "Exit Code: 1" | Out-File -FilePath $debugLog -Append -Encoding UTF8
    }
    catch {
        # Ignoriere Fehler
    }
    exit 1
}

try {
    "Log-Verzeichnis erfolgreich initialisiert: $($script:LogDir)" | Out-File -FilePath $debugLog -Append -Encoding UTF8
}
catch {
    # Ignoriere Fehler
}

$script:LocalLogFile = $null

function Write-LocalLog {
    param(
        [string]$Text,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
        [string]$Level = "INFO"
    )

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Text"
    
    $color = switch ($Level) {
        "INFO"    { "White" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "DEBUG"   { "Cyan" }
        default   { "White" }
    }

    Write-Host $line -ForegroundColor $color
    
    if (-not $script:LocalLogFile) {
        if (-not $script:LogDir) {
            Write-Host "FEHLER: Log-Verzeichnis nicht initialisiert!" -ForegroundColor Red
            return
        }
        Write-Host "WARNUNG: Keine benutzerspezifische Log-Datei initialisiert - Log wird nicht geschrieben!" -ForegroundColor Yellow
        return
    }
    
    if ((-not $script:LogDir) -or ($script:LogDir -notlike "\\*")) {
        Write-Host "FEHLER: Log-Verzeichnis ist nicht im Netzwerk: $($script:LogDir)" -ForegroundColor Red
        return
    }
    
    try {
        $line | Out-File -FilePath $script:LocalLogFile -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Host "FEHLER: Log-Datei konnte nicht geschrieben werden: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-InteractiveUserNames {
    $users = [System.Collections.Generic.HashSet[string]]::new()

    $primary = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if ($primary) { 
        $null = $users.Add($primary)
    }

    try {
        Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.UserName) { 
                $null = $users.Add($_.UserName)
            }
        }
    }
    catch {
        # Fallback
    }

    if ($users.Count -eq 0) {
        throw "Kein interaktiv angemeldeter Benutzer gefunden."
    }

    return $users | ForEach-Object { $_.Split('\')[-1].Trim() } | Where-Object { $_ } | Sort-Object -Unique
}

function Test-ServerAvailable {
    if (-not (Test-Path $ServerRoot)) {
        throw "Server ist nicht erreichbar."
    }
}

function Import-ActiveDirectoryModule {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-ProfilePathFromADSI {
    param([string]$UserName)

    try {
        $rootPath = "LDAP://$ADBaseDN"
        $root = New-Object System.DirectoryServices.DirectoryEntry($rootPath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$UserName))"
        $null = $searcher.PropertiesToLoad.Add("profilePath")
        $result = $searcher.FindOne()
        
        if ($result -and $result.Properties["profilePath"] -and $result.Properties["profilePath"].Count -gt 0) {
            $profilePath = $result.Properties["profilePath"][0]
            Write-LocalLog "Profil via ADSI gefunden: $profilePath" "SUCCESS"
            return $profilePath -replace '%USERNAME%', $UserName
        }
        
        Write-LocalLog "ADSI lieferte keinen Profilpfad fuer $UserName." "WARN"
    }
    catch {
        Write-LocalLog "ADSI-Abfrage fehlgeschlagen fuer ${UserName}: $($_.Exception.Message)" "WARN"
    }

    return $null
}

function Resolve-ProfilePath {
    param(
        [string]$UserName,
        [bool]$ADAvailable
    )

    $profilSuffix = ""
    $path = $null

    if ($ADAvailable) {
        try {
            $adUser = Get-ADUser -Identity $UserName -Properties profilePath -ErrorAction Stop
            if ($adUser.profilePath) {
                $path = $adUser.profilePath -replace '%USERNAME%', $UserName
                $profilSuffix = Split-Path $path -Leaf
                Write-LocalLog "Profil via AD gefunden: $path" "SUCCESS"
            }
            else {
                Write-LocalLog "AD-Eintrag ohne Profilpfad - Fallback." "WARN"
            }
        }
        catch {
            Write-LocalLog "AD-Abfrage fehlgeschlagen: $($_.Exception.Message) - Fallback." "WARN"
        }
    }

    if (-not $path) {
        $adsiPath = Get-ProfilePathFromADSI -UserName $UserName
        if ($adsiPath) {
            $path = $adsiPath
            $profilSuffix = Split-Path $path -Leaf
        }
    }

    if ($path -and (-not (Test-Path "$path\AppData\Roaming"))) {
        Write-LocalLog "AD/ADSI-Pfad ohne AppData\Roaming gefunden - Fallback-Suche wird verwendet." "WARN"
        $path = $null
        $profilSuffix = ""
    }

    if (-not $path) {
        $profileFolders = @()
        
        try {
            if (Test-Path $ServerRoot) {
                $profileFolders += Get-ChildItem $ServerRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Profile*" }
            }
        }
        catch {
            Write-LocalLog "Fehler beim Zugriff auf ServerRoot: $($_.Exception.Message)" "WARN"
        }
        
        foreach ($extraRoot in $AdditionalProfileRoots) {
            if (Test-Path $extraRoot) {
                try {
                    $profileFolders += Get-Item $extraRoot -ErrorAction SilentlyContinue
                }
                catch {
                    Write-LocalLog "Fehler beim Zugriff auf zusaetzliches Profil-Root: $extraRoot" "WARN"
                }
            }
        }
        
        $profileFolders = $profileFolders | Sort-Object -Property Name -Unique
        
        foreach ($folder in $profileFolders) {
            foreach ($suffix in @(".V6", ".V5", ".V2", "")) {
                $testPath = Join-Path -Path $folder.FullName -ChildPath "$UserName$suffix"
                if (Test-Path "$testPath\AppData\Roaming") {
                    $path = $testPath
                    $profilSuffix = "$UserName$suffix"
                    Write-LocalLog "Profil via Fallback gefunden: $path" "SUCCESS"
                    break
                }
            }
            if ($path) { break }
        }
    }

    if (-not $path) {
        throw "Kein Roaming-Profil fuer $UserName gefunden."
    }

    return [PSCustomObject]@{
        Path        = $path
        Suffix      = $profilSuffix
        RoamingPath = "$path\AppData\Roaming"
    }
}

function Stop-LockingApps {
    param([string]$UserName)

    $appsToStop = @("Teams","ms-teams","Slack","Zoom","Discord")
    $stopped = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($app in $appsToStop) {
        try {
            $processes = Get-Process -Name $app -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$UserName" }
            foreach ($proc in $processes) {
                if (-not $DryRun) {
                    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                $null = $stopped.Add($app)
            }
        }
        catch {
            Write-LocalLog "Fehler beim Beenden von ${app}: $($_.Exception.Message)" "WARN"
        }
    }

    if ($stopped.Count -gt 0) {
        Write-LocalLog "Beendete Apps: $($stopped -join ', ')" "SUCCESS"
    }
    else {
        Write-LocalLog "Keine sperrenden Apps gefunden." "INFO"
    }
}

function Measure-DirectoryMB {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return 0
    }

    $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { 
        $sum = 0 
    }
    return [math]::Round($sum / 1MB, 2)
}

function Remove-BloatTarget {
    param([string]$Path)

    $sizeBefore = Measure-DirectoryMB -Path $Path
    if ($sizeBefore -le 0) {
        return 0
    }

    if (-not $DryRun) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-LocalLog "Loeschen fehlgeschlagen fuer Pfad: $($_.Exception.Message)" "ERROR"
            return 0
        }

        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    $sizeStr = [string]$sizeBefore + " MB"
    Write-LocalLog "Ordner bereinigt: $Path ($sizeStr)" "SUCCESS"
    return $sizeBefore
}

$BloatFolders = @(
    "Microsoft\Teams\Cache",
    "Microsoft\Teams\GPUCache",
    "Microsoft\Teams\Code Cache",
    "Microsoft\Teams\IndexedDB",
    "Microsoft\Teams\blob_storage",
    "Microsoft\Teams\databases",
    "Microsoft\Teams\Local Storage",
    "Microsoft\Teams\Service Worker",
    "Microsoft\OneDrive\logs",
    "Microsoft\OneDrive\Cache",
    "Microsoft\Edge\User Data\Default\Cache",
    "Microsoft\Edge\User Data\Default\Code Cache",
    "Microsoft\Edge\User Data\Default\GPUCache",
    "Microsoft\Outlook\RoamCache",
    "Slack\Cache",
    "Slack\Code Cache",
    "Slack\GPUCache",
    "Zoom\data",
    "Zoom\logs",
    "Code\Cache",
    "Code\CachedData",
    "Code\GPUCache",
    "discord\Cache",
    "discord\Code Cache",
    "discord\GPUCache",
    "Adobe\Common\Media Cache Files",
    "Adobe\Common\Peak Files",
    "Google\Chrome\User Data\Default\Cache",
    "Google\Chrome\User Data\Default\Code Cache"
)

function Clear-BloatCache {
    param(
        [string]$BasePath,
        [string]$Scope
    )

    $freed = 0
    
    foreach ($bloat in $BloatFolders) {
        $target = Join-Path -Path $BasePath -ChildPath $bloat
        if (Test-Path $target) {
            Write-LocalLog "Bereinige ($Scope): $target" "DEBUG"
            $freed += Remove-BloatTarget -Path $target
        }
        else {
            Write-LocalLog "Nicht gefunden ($Scope): $target" "DEBUG"
        }
    }
    
    return $freed
}

function Invoke-Cleanup {
    try {
        Test-ServerAvailable
    }
    catch {
        Write-Host "WARNUNG: Server-Verfuegbarkeitspruefung fehlgeschlagen: $($_.Exception.Message) - fahre fort." -ForegroundColor Yellow
    }

    try {
        $userNames = Get-InteractiveUserNames
    }
    catch {
        Write-Host "FEHLER: Fehler beim Ermitteln der Benutzer: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
    
    # Initialisiere benutzerspezifische Logs frueh, damit alle Logs dort landen
    $totalFreedGB = 0
    $userLogFiles = @()
    
    foreach ($userName in $userNames) {
        $safeUserName = $userName -replace '[<>:"/\\|?*]', '_'
        $userLogFile = Join-Path -Path $script:LogDir -ChildPath ("RoamingCleanup_" + $safeUserName + ".log")
        if (-not ($userLogFiles -contains $userLogFile)) {
            $userLogFiles += $userLogFile
        }
    }
    
    # AD-Modul laden (wird in alle benutzerspezifischen Logs geschrieben)
    $adAvailable = $false
    if ($userLogFiles.Count -gt 0) {
        # Tempor�r erste Log-Datei setzen f�r AD-Modul-Logs
        $script:LocalLogFile = $userLogFiles[0]
    }
    
    try {
        $adAvailable = Import-ActiveDirectoryModule
    }
    catch {
        Write-Host "WARNUNG: Fehler beim Laden des AD-Moduls - Fallback aktiv." -ForegroundColor Yellow
        $adAvailable = $false
    }

    foreach ($userName in $userNames) {
        $safeUserName = $userName -replace '[<>:"/\\|?*]', '_'
        $userLogFile = Join-Path -Path $script:LogDir -ChildPath ("RoamingCleanup_" + $safeUserName + ".log")
        $script:LocalLogFile = $userLogFile
        
        try {
            Write-LocalLog "=== Script gestartet (DryRun=$DryRun) ===" "INFO"
            Write-LocalLog "Log-Verzeichnis: $($script:LogDir)" "INFO"
            Write-LocalLog "Bearbeite Benutzer: $userName" "INFO"
            
            # AD-Modul-Status in benutzerspezifisches Log schreiben
            if ($adAvailable) {
                Write-LocalLog "AD-Modul geladen." "SUCCESS"
            }
            else {
                Write-LocalLog "AD-Modul nicht verfuegbar. Fallback aktiv." "WARN"
            }
            
            $userNameLower = $userName.ToLower()
            $isExcluded = $ExcludedUsers | Where-Object { $_.ToLower() -eq $userNameLower } | Select-Object -First 1
            
            if ($isExcluded) {
                Write-LocalLog "Benutzer $userName ausgeschlossen - Uebersprung." "WARN"
                continue
            }
        }
        catch {
            Write-Host "FEHLER: Fehler bei Benutzer-Verarbeitung: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        try {
            $profileInfo = Resolve-ProfilePath -UserName $userName -ADAvailable $adAvailable
        }
        catch {
            Write-LocalLog "Profilaufloesung fehlgeschlagen fuer ${userName}: $($_.Exception.Message)" "WARN"
            continue
        }

        try {
            $localRoaming = "C:\Users\$userName\AppData\Roaming"

            Stop-LockingApps -UserName $userName

            $freedServer = Clear-BloatCache -BasePath $profileInfo.RoamingPath -Scope "Server"
            $freedLocal = 0
            
            if (Test-Path $localRoaming) {
                $freedLocal = Clear-BloatCache -BasePath $localRoaming -Scope "Lokal"
            }
            else {
                Write-LocalLog "Lokaler Roaming-Pfad fehlt: $localRoaming" "WARN"
            }

            $serverFreedGB = [math]::Round($freedServer / 1024, 3)
            $localFreedGB = [math]::Round($freedLocal / 1024, 3)
            $totalFreedGB += $serverFreedGB

            # Format angepasst fuer kumulatives Script: "Cleanup abgeschlossen fuer BENUTZER � Server freigegeben: X.XXX GB"
            Write-LocalLog "Cleanup abgeschlossen fuer $userName � Server freigegeben: $serverFreedGB GB, Lokal freigegeben: $localFreedGB GB (DryRun=$DryRun)" "SUCCESS"
            Write-LocalLog "=== Script beendet ===" "INFO"
        }
        catch {
            Write-LocalLog "Fehler beim Cleanup fuer ${userName}: $($_.Exception.Message)" "ERROR"
            Write-LocalLog "=== Script beendet (mit Fehler) ===" "ERROR"
            continue
        }
    }
    
    $logCount = $userLogFiles.Count
    if ($logCount -gt 0) {
        $logSummary = "Benutzer-Logs: $logCount Datei(en)"
    }
    else {
        $logSummary = "Keine Benutzer verarbeitet"
    }
    
    Write-Host ""
    Write-Host "Fertig! $logSummary | Log-Verzeichnis: $($script:LogDir) | Gesamt Server-Freigabe: $totalFreedGB GB" -ForegroundColor Cyan

    return $totalFreedGB
}

try {
    Invoke-Cleanup | Out-Null
    exit 0
}
catch {
    # Versuche Fehler in die benutzerspezifischen Logs zu schreiben, falls vorhanden
    if ($script:LocalLogFile) {
        Write-LocalLog "KRITISCHER FEHLER: $($_.Exception.Message)" "ERROR"
        Write-LocalLog "StackTrace: $($_.ScriptStackTrace)" "ERROR"
    }
    else {
        Write-Host "KRITISCHER FEHLER: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
        Write-Host "Log-Verzeichnis nicht verfuegbar!" -ForegroundColor Red
    }
    exit 1
}

