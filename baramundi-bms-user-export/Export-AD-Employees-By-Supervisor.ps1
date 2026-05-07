# ==================================================================
# Exportiert die zugewiesenen Mitarbeiter von Vorgesetzten aus dem AD
# ==================================================================
# 
# Dieses Script liest die direkten Untergebenen (Mitarbeiter) von
# bestimmten Vorgesetzten aus dem Active Directory aus und erstellt
# eine CSV-Datei mit den Ergebnissen.
#
# Vorgesetzte werden anhand ihrer sAMAccountName (pre-Windows 2000)
# identifiziert.
#
# Parameter (optional):
#   -VorgesetzteListe: Array von sAMAccountNames
#   -OutputDirectory: Zielverzeichnis (z.B. c:\edv)
#   -OutputFileName: Dateiname ohne .csv
# ==================================================================

param(
    [string[]]$VorgesetzteListe,
    [string]$OutputDirectory,
    [string]$OutputFileName
)

$ErrorActionPreference = "Continue"

# Konfiguration
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Get-Location | Select-Object -ExpandProperty Path
}

$OutputDir = if ($OutputDirectory) { $OutputDirectory } else { $ScriptDir }
$LogDir = Join-Path $OutputDir "Logs"
$LogFile = Join-Path $LogDir "Export-Mitarbeiter-Vorgesetzte_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
$CsvFile = if ($OutputFileName) {
    Join-Path $OutputDir "$OutputFileName.csv"
} else {
    Join-Path $OutputDir "Mitarbeiter-Vorgesetzte_$(Get-Date -Format 'yyyy-MM-dd').csv"
}

# Liste der Vorgesetzten (sAMAccountName - pre-Windows 2000 Benutzernamen)
$Vorgesetzte = if ($VorgesetzteListe) { $VorgesetzteListe } else { @(
    "<SUPERVISOR-SAMACCOUNTNAME-1>",
    "<SUPERVISOR-SAMACCOUNTNAME-2>"
) }

# Erstelle Log-Verzeichnis falls nicht vorhanden
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Logging-Funktion
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Host ""
Write-Host "=== Export Mitarbeiter von Vorgesetzten ===" -ForegroundColor Cyan
Write-Host ""

# Prüfe ob ActiveDirectory-Modul verfügbar ist
Write-Log "Prüfe ActiveDirectory-Modul..." "INFO"
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Log "FEHLER: ActiveDirectory-Modul nicht gefunden. Bitte installieren Sie RSAT: Active Directory Domain Services Tools" "ERROR"
    exit 1
}

# Lade ActiveDirectory-Modul
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory-Modul geladen" "SUCCESS"
} catch {
    Write-Log "FEHLER: ActiveDirectory-Modul konnte nicht geladen werden: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Array für alle Ergebnisse
$allResults = @()

# Verarbeite jeden Vorgesetzten
foreach ($vorgesetzterSamAccountName in $Vorgesetzte) {
    Write-Host ""
    Write-Host "=== Vorgesetzter: $vorgesetzterSamAccountName ===" -ForegroundColor Yellow
    Write-Log "Verarbeite Vorgesetzten: $vorgesetzterSamAccountName" "INFO"
    
    try {
        # Finde Vorgesetzten im AD
        $vorgesetzter = Get-ADUser -Filter "sAMAccountName -eq '$vorgesetzterSamAccountName'" -Properties DisplayName, DistinguishedName, Manager -ErrorAction Stop
        
        if (-not $vorgesetzter) {
            Write-Log "WARNUNG: Vorgesetzter '$vorgesetzterSamAccountName' nicht im AD gefunden" "WARNING"
            Write-Host "  [WARNUNG] Vorgesetzter nicht gefunden" -ForegroundColor Yellow
            continue
        }
        
        Write-Log "Vorgesetzter gefunden: $($vorgesetzter.DisplayName) ($($vorgesetzter.DistinguishedName))" "INFO"
        Write-Host "  Name: $($vorgesetzter.DisplayName)" -ForegroundColor Green
        Write-Host "  DN: $($vorgesetzter.DistinguishedName)" -ForegroundColor Gray
        
        # Finde alle direkten Untergebenen (Mitarbeiter)
        # Ein Mitarbeiter hat diesen Vorgesetzten als Manager
        $mitarbeiter = Get-ADUser -Filter "Manager -eq '$($vorgesetzter.DistinguishedName)'" -Properties DisplayName, sAMAccountName, UserPrincipalName, EmailAddress, Department, Title, Enabled -ErrorAction Stop
        
        Write-Log "Gefundene Mitarbeiter: $($mitarbeiter.Count)" "INFO"
        Write-Host "  Mitarbeiter gefunden: $($mitarbeiter.Count)" -ForegroundColor Green
        
        if ($mitarbeiter.Count -eq 0) {
            Write-Log "Keine Mitarbeiter für Vorgesetzten '$vorgesetzterSamAccountName' gefunden" "INFO"
            Write-Host "  [INFO] Keine Mitarbeiter zugewiesen" -ForegroundColor Gray
        } else {
            # Verarbeite jeden Mitarbeiter
            foreach ($ma in $mitarbeiter) {
                $result = [PSCustomObject]@{
                    Vorgesetzter_sAMAccountName = $vorgesetzterSamAccountName
                    Vorgesetzter_DisplayName = $vorgesetzter.DisplayName
                    Vorgesetzter_DN = $vorgesetzter.DistinguishedName
                    Mitarbeiter_sAMAccountName = $ma.sAMAccountName
                    Mitarbeiter_DisplayName = $ma.DisplayName
                    Mitarbeiter_UserPrincipalName = if ($ma.UserPrincipalName) { $ma.UserPrincipalName } else { "" }
                    Mitarbeiter_EmailAddress = if ($ma.EmailAddress) { $ma.EmailAddress } else { "" }
                    Mitarbeiter_Department = if ($ma.Department) { $ma.Department } else { "" }
                    Mitarbeiter_Title = if ($ma.Title) { $ma.Title } else { "" }
                    Mitarbeiter_Enabled = $ma.Enabled
                    Mitarbeiter_DN = $ma.DistinguishedName
                }
                
                $allResults += $result
                
                Write-Log "  Mitarbeiter: $($ma.DisplayName) ($($ma.sAMAccountName))" "INFO"
            }
        }
        
    } catch {
        Write-Log "FEHLER beim Verarbeiten von Vorgesetzten '$vorgesetzterSamAccountName': $($_.Exception.Message)" "ERROR"
        Write-Host "  [FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Exportiere Ergebnisse in CSV
Write-Host ""
Write-Host "=== Exportiere Ergebnisse ===" -ForegroundColor Cyan
Write-Host ""

if ($allResults.Count -gt 0) {
    try {
        $allResults | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
        Write-Log "CSV-Datei erstellt: $CsvFile" "SUCCESS"
        Write-Host "CSV-Datei erstellt: $CsvFile" -ForegroundColor Green
        Write-Host "Anzahl Einträge: $($allResults.Count)" -ForegroundColor Green
    } catch {
        Write-Log "FEHLER beim Erstellen der CSV-Datei: $($_.Exception.Message)" "ERROR"
        Write-Host "FEHLER beim Erstellen der CSV-Datei: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Log "Keine Mitarbeiter gefunden - erstelle leere CSV-Datei" "WARNING"
    Write-Host "Keine Mitarbeiter gefunden" -ForegroundColor Yellow
    
    # Erstelle leere CSV mit Spaltenüberschriften
    $emptyResult = [PSCustomObject]@{
        Vorgesetzter_sAMAccountName = ""
        Vorgesetzter_DisplayName = ""
        Vorgesetzter_DN = ""
        Mitarbeiter_sAMAccountName = ""
        Mitarbeiter_DisplayName = ""
        Mitarbeiter_UserPrincipalName = ""
        Mitarbeiter_EmailAddress = ""
        Mitarbeiter_Department = ""
        Mitarbeiter_Title = ""
        Mitarbeiter_Enabled = $false
        Mitarbeiter_DN = ""
    }
    
    try {
        $emptyResult | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
        Write-Log "Leere CSV-Datei erstellt: $CsvFile" "INFO"
    } catch {
        Write-Log "FEHLER beim Erstellen der leeren CSV-Datei: $($_.Exception.Message)" "ERROR"
    }
}

# Zusammenfassung
Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host ""

$vorgesetzteMitMitarbeitern = ($allResults | Select-Object -Unique Vorgesetzter_sAMAccountName).Count
$vorgesetzteOhneMitarbeiter = $Vorgesetzte.Count - $vorgesetzteMitMitarbeitern

Write-Host "Vorgesetzte verarbeitet: $($Vorgesetzte.Count)" -ForegroundColor Yellow
Write-Host "  - Mit Mitarbeitern: $vorgesetzteMitMitarbeitern" -ForegroundColor Green
Write-Host "  - Ohne Mitarbeiter: $vorgesetzteOhneMitarbeiter" -ForegroundColor $(if ($vorgesetzteOhneMitarbeiter -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""
Write-Host "Gesamtanzahl Mitarbeiter: $($allResults.Count)" -ForegroundColor Green
Write-Host ""

# Zeige Aufschlüsselung nach Vorgesetzten
if ($allResults.Count -gt 0) {
    Write-Host "Aufschlüsselung nach Vorgesetzten:" -ForegroundColor Yellow
    foreach ($vg in $Vorgesetzte) {
        $anzahl = ($allResults | Where-Object { $_.Vorgesetzter_sAMAccountName -eq $vg }).Count
        $displayName = ($allResults | Where-Object { $_.Vorgesetzter_sAMAccountName -eq $vg } | Select-Object -First 1 -Unique).Vorgesetzter_DisplayName
        if (-not $displayName) {
            $displayName = "Nicht gefunden"
        }
        Write-Host "  - $vg ($displayName): $anzahl Mitarbeiter" -ForegroundColor Cyan
    }
    Write-Host ""
}

Write-Host "CSV-Datei: $CsvFile" -ForegroundColor Cyan
Write-Host "Log-Datei: $LogFile" -ForegroundColor Gray
Write-Host ""

Write-Log "=== Export abgeschlossen ===" "INFO"

