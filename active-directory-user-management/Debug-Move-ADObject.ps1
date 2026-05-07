# Debug: Warum schlaegt Move-ADObject fuer einen bestimmten Account fehl?
# Fuehrt Diagnose durch und testet ADSI MoveHere als Alternative

param([string]$SamAccountName = "<SAMACCOUNTNAME>")

$TargetOU = "OU=Nicht aktiv seit 6+ Wochen (Script deaktivierung),OU=Deaktivierte Benutzer (Unternehmen verlassen),DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"

Import-Module ActiveDirectory -ErrorAction Stop

Write-Host "=== Diagnose fuer $SamAccountName ===" -ForegroundColor Cyan
$user = Get-ADUser $SamAccountName -Properties DistinguishedName, ObjectGUID, CanonicalName, parentGUID -ErrorAction Stop
Write-Host "DN: $($user.DistinguishedName)"
Write-Host "ObjectGUID: $($user.ObjectGUID)"
Write-Host "CanonicalName: $($user.CanonicalName)"

$parentDN = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
Write-Host "`nParent DN: $parentDN"

Write-Host "`n--- Pruefe Parent-OU ---" -ForegroundColor Yellow
try {
    $parent = Get-ADObject -Identity $parentDN -ErrorAction Stop
    Write-Host "Parent existiert: $($parent.DistinguishedName)" -ForegroundColor Green
} catch {
    Write-Host "Parent-OU existiert NICHT oder ist verwaist: $_" -ForegroundColor Red
}

Write-Host "`n--- Pruefe Ziel-OU ---" -ForegroundColor Yellow
try {
    $target = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop
    Write-Host "Ziel-OU existiert: $($target.DistinguishedName)" -ForegroundColor Green
} catch {
    Write-Host "Ziel-OU existiert NICHT: $_" -ForegroundColor Red
}

Write-Host "`n--- Test 1: Move-ADObject mit ObjectGUID ---" -ForegroundColor Yellow
$moveOk = $false
try {
    Move-ADObject -Identity $user.ObjectGUID -TargetPath $TargetOU -ErrorAction Stop
    Write-Host "Move-ADObject ERFOLG" -ForegroundColor Green
    $moveOk = $true
} catch {
    Write-Host "Move-ADObject Fehler: $_" -ForegroundColor Red
}

if (-not $moveOk) {
    Write-Host "`n--- Test 2: ADSI MoveHere (GUID-Pfad) ---" -ForegroundColor Yellow
    $user = Get-ADUser $SamAccountName -Properties ObjectGUID -ErrorAction Stop
    $sourcePath = "LDAP://<GUID=$($user.ObjectGUID)>"
    try {
        $targetEntry = [ADSI]("LDAP://$TargetOU")
        $targetEntry.MoveHere($sourcePath, $null)
        Write-Host "ADSI MoveHere ERFOLG" -ForegroundColor Green
    } catch {
        Write-Host "ADSI MoveHere Fehler: $_" -ForegroundColor Red
    }
}
