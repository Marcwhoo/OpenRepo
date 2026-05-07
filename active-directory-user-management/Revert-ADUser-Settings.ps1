# Rueckgaengig: User wieder aktivieren, zurueckverschieben, Beschreibung zuruecksetzen

param([string]$SamAccountName = "<SAMACCOUNTNAME>")

Import-Module ActiveDirectory -ErrorAction Stop

$u = Get-ADUser $SamAccountName -Properties Description, ObjectGUID -ErrorAction Stop

Enable-ADAccount $SamAccountName
Write-Host "Konto wieder aktiviert." -ForegroundColor Green

if ($u.Description -match '[|]\s*OU:\s*(.+)$') {
    $originalOU = $Matches[1].Trim()
    if ($originalOU -match '^\s*\S+,\s*(OU=.+)$') { $originalOU = $Matches[1] }
    try {
        Move-ADObject -Identity $u.ObjectGUID -TargetPath $originalOU -ErrorAction Stop
        Write-Host "Zurueckverschoben nach: $originalOU" -ForegroundColor Green
    } catch {
        Write-Host "Verschiebung fehlgeschlagen: $_" -ForegroundColor Yellow
    }
}

$desc = $u.Description
if ($desc -match '^(.*?)\s*[|]\s*OU:\s*.+$') {
    $original = $Matches[1].Trim()
    Set-ADUser $SamAccountName -Description $(if ($original) { $original } else { $null })
    Write-Host "Beschreibung zurueckgesetzt." -ForegroundColor Green
} elseif ($desc -and $desc -match 'OU:\s*OU=') {
    Set-ADUser $SamAccountName -Description $null
    Write-Host "Beschreibung geleert." -ForegroundColor Green
} else {
    Write-Host "Beschreibung bereits bereinigt oder kein OU-Anhang vorhanden." -ForegroundColor Green
}
