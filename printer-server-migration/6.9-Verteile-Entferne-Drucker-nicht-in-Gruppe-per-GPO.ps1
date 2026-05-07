# Script zum Verteilen des Client-Scripts zum Entfernen von Druckern per GPO
# Entfernt Drucker, wenn Benutzer nicht mehr in Sicherheitsgruppen sind

param(
    [Parameter(Mandatory=$false)]
    [string]$GPOName = "Drucker - Entferne Drucker wenn nicht in Gruppe",
    [Parameter(Mandatory=$false)]
    [string]$ScriptName = "6.8-Client-Entferne-Drucker-nicht-in-Gruppe-Bereinigt.ps1",
    [Parameter(Mandatory=$false)]
    [string]$PrintServer = "<PRINT-SERVER-1>-01",
    [Parameter(Mandatory=$false)]
    [string]$GroupOU = "OU=Drucker,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
)

Write-Host "=== Verteile Client-Script zum Entfernen von Druckern per GPO ===" -ForegroundColor Cyan
Write-Host "GPO-Name: $GPOName" -ForegroundColor Yellow
Write-Host "Script-Name: $ScriptName" -ForegroundColor Yellow
Write-Host "Druckerserver: $PrintServer" -ForegroundColor Yellow
Write-Host "Gruppen-OU: $GroupOU" -ForegroundColor Yellow
Write-Host ""

# Prüfe ob Script existiert
$scriptPath = Join-Path $PSScriptRoot $ScriptName
if (-not (Test-Path $scriptPath)) {
    Write-Host "[FEHLER] Script nicht gefunden: $scriptPath" -ForegroundColor Red
    exit 1
}

# Hole Domain-Informationen
$domainName = (Get-ADDomain).DNSRoot
$sysvolPath = "\\$domainName\SYSVOL\$domainName\Policies"

# Erstelle oder hole GPO
try {
    $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        Write-Host "Erstelle neue GPO: $GPOName" -ForegroundColor Yellow
        $gpo = New-GPO -Name $GPOName
        Write-Host "[OK] GPO erstellt" -ForegroundColor Green
    } else {
        Write-Host "GPO bereits vorhanden: $GPOName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FEHLER] Konnte GPO nicht erstellen/abrufen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Pfad zum Scripts-Ordner in der GPO
$gpoScriptsPath = Join-Path $sysvolPath "$($gpo.Id)\User\Scripts\Logon"
if (-not (Test-Path $gpoScriptsPath)) {
    New-Item -ItemType Directory -Path $gpoScriptsPath -Force | Out-Null
    Write-Host "[OK] Scripts-Ordner erstellt" -ForegroundColor Green
}

# Kopiere Script in GPO-Ordner
$targetScriptPath = Join-Path $gpoScriptsPath $ScriptName
try {
    Copy-Item -Path $scriptPath -Destination $targetScriptPath -Force
    Write-Host "[OK] Script kopiert nach: $targetScriptPath" -ForegroundColor Green
} catch {
    Write-Host "[FEHLER] Konnte Script nicht kopieren: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Konfiguriere GPO: Script bei Anmeldung ausführen
try {
    # Erstelle Script-Befehl mit Parametern
    $scriptCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScriptPath`" -PrintServer '$PrintServer' -GroupOU '$GroupOU'"
    
    Write-Host "[INFO] Script wurde in GPO kopiert" -ForegroundColor Yellow
    Write-Host "[INFO] Bitte konfigurieren Sie die GPO manuell:" -ForegroundColor Yellow
    Write-Host "       1. Öffnen Sie Group Policy Management" -ForegroundColor Yellow
    Write-Host "       2. Bearbeiten Sie die GPO: $GPOName" -ForegroundColor Yellow
    Write-Host "       3. Gehen Sie zu: User Configuration > Policies > Windows Settings > Scripts (Logon/Logoff)" -ForegroundColor Yellow
    Write-Host "       4. Fügen Sie das Script hinzu: $ScriptName" -ForegroundColor Yellow
    Write-Host "       5. Oder verwenden Sie: User Configuration > Preferences > Control Panel Settings > Scheduled Tasks" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Alternative: Verwenden Sie einen Scheduled Task per GPO Preferences" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Script-Befehl:" -ForegroundColor Cyan
    Write-Host $scriptCommand -ForegroundColor White
    
} catch {
    Write-Host "[WARNUNG] Konnte GPO nicht automatisch konfigurieren: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "[INFO] Bitte konfigurieren Sie die GPO manuell" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "GPO-Name: $GPOName" -ForegroundColor Green
Write-Host "GPO-GUID: $($gpo.Id)" -ForegroundColor Green
Write-Host "Script-Pfad in GPO: $targetScriptPath" -ForegroundColor Green
Write-Host "Druckerserver: $PrintServer" -ForegroundColor Green
Write-Host "Gruppen-OU: $GroupOU" -ForegroundColor Green
Write-Host ""
Write-Host "HINWEIS: Das Script entfernt alle Drucker vom neuen Server, für die" -ForegroundColor Yellow
Write-Host "        der Benutzer nicht mehr in der entsprechenden Sicherheitsgruppe ist." -ForegroundColor Yellow
