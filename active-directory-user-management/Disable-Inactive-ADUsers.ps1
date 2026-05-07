# Als Domain-Admin ausfuehren
# Deaktiviert Benutzer die 6+ Wochen nicht angemeldet waren

$InactiveDays = 42  # 6 Wochen

$ExclusionList = @("Administrator", "Guest")

$ExcludedOUs = @(
    "CN=Users,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    "OU=EDV,OU=Abteilungen,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
)

Import-Module ActiveDirectory -ErrorAction Stop

# Ziel-OU dynamisch aus AD (vermeidet DN-Syntaxfehler bei Sonderzeichen wie +)
$domainDN = (Get-ADDomain).DistinguishedName
$parentOU = Get-ADOrganizationalUnit -Filter "Name -eq 'Deaktivierte Benutzer (Unternehmen verlassen)'" -SearchBase $domainDN -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $parentOU) { Write-Host "Ziel-OU-Parent nicht gefunden." -ForegroundColor Red; exit }
$targetOU = Get-ADOrganizationalUnit -Filter "Name -eq 'Nicht aktiv seit 6+ Wochen (Script deaktivierung)'" -SearchBase $parentOU.DistinguishedName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $targetOU) { Write-Host "Ziel-OU nicht gefunden." -ForegroundColor Red; exit }
$TargetOU = $targetOU.DistinguishedName

$cutoffDate = (Get-Date).AddDays(-$InactiveDays)

# Nur aktive (Enabled) Konten
$users = Get-ADUser -Filter {Enabled -eq $true} -Properties LastLogonTimestamp, Description, DistinguishedName -ResultSetSize $null |
    Where-Object {
        $u = $_
        $u.LastLogonTimestamp -and
        [DateTime]::FromFileTime($u.LastLogonTimestamp) -lt $cutoffDate -and
        $u.SamAccountName -notin $ExclusionList -and
        -not ($ExcludedOUs | Where-Object { $u.DistinguishedName -like "*$_" })
    } | Sort-Object SamAccountName

$AusnahmenPfad = "C:\edv\ausnahmen.txt"
$DeclinedUsers = @()

if ($users.Count -eq 0) {
    Write-Host "Keine Konten betroffen." -ForegroundColor Green
    exit
}

Write-Host "`n--- Konten zur Einzelbestaetigung ($($users.Count) Stueck) ---`n" -ForegroundColor Yellow

foreach ($user in $users) {
    $lastLogon = [DateTime]::FromFileTime($user.LastLogonTimestamp).ToString("dd.MM.yyyy")
    Write-Host "  $($user.SamAccountName)  |  Letzte Anmeldung: $lastLogon" -ForegroundColor Gray
    $antwort = (Read-Host "  Deaktivieren? (j/n)").Trim().ToLower()
    if ($antwort -eq "j") {
        $ouPath = ($user.DistinguishedName -replace '^CN=(?:[^,]|\\.)*,', '')
        $newDesc = if ($user.Description) { "$($user.Description) | OU: $ouPath" } else { "OU: $ouPath" }
        $moved = $false
        try {
            Move-ADObject -Identity $user.ObjectGUID -TargetPath $TargetOU -ErrorAction Stop
            $moved = $true
        } catch {
            try {
                $rdn = if ($user.DistinguishedName -match '^(CN=(?:[^,]|\\.)*),') { $Matches[1] } else { "CN=$($user.Name)" }
                $sourcePath = "LDAP://<GUID=$($user.ObjectGUID)>"
                $targetEntry = [ADSI]("LDAP://$TargetOU")
                $targetEntry.MoveHere($sourcePath, $rdn)
                $moved = $true
            } catch {
                Write-Host "  Verschiebung fehlgeschlagen, deaktiviere ohne Verschiebung: $_" -ForegroundColor Yellow
            }
        }
        Set-ADUser -Identity $user.ObjectGUID -Description $newDesc
        Disable-ADAccount -Identity $user.ObjectGUID
        Write-Host "  Deaktiviert: $($user.SamAccountName)" -ForegroundColor Green
    } else {
        $DeclinedUsers += $user.SamAccountName
        Write-Host "  Uebersprungen: $($user.SamAccountName)" -ForegroundColor Yellow
    }
}

if ($DeclinedUsers.Count -gt 0) {
    $dir = Split-Path $AusnahmenPfad -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $alle = $ExclusionList + $DeclinedUsers | Sort-Object -Unique
    $content = "`$ExclusionList = @(" + [Environment]::NewLine + ($alle | ForEach-Object { "    `"$_`"" }) -join ("," + [Environment]::NewLine) + [Environment]::NewLine + ")"
    Set-Content -Path $AusnahmenPfad -Value $content -Encoding UTF8
    Write-Host "`nAusnahmen gespeichert: $AusnahmenPfad" -ForegroundColor Cyan
}

Write-Host "`n--- Fertig ---" -ForegroundColor Green
