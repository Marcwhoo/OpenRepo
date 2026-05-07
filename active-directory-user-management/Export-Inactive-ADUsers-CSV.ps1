# Als Domain-Admin ausfuehren
# Schreibt alle Benutzer die deaktiviert werden wuerden in CSV

$InactiveDays = 42
$ExclusionList = @("Administrator", "Guest")
$ExcludedOUs = @(
    "CN=Users,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>",
    "OU=EDV,OU=Abteilungen,DC=<DOMAIN>,DC=<TLD1>,DC=<TLD2>"
)

$OutputPath = "C:\edv\inaktive-benutzer.csv"

Import-Module ActiveDirectory -ErrorAction Stop
$cutoffDate = (Get-Date).AddDays(-$InactiveDays)

$users = Get-ADUser -Filter {Enabled -eq $true} -Properties LastLogonTimestamp, Description, DistinguishedName -ResultSetSize $null |
    Where-Object {
        $u = $_
        $u.LastLogonTimestamp -and
        [DateTime]::FromFileTime($u.LastLogonTimestamp) -lt $cutoffDate -and
        $u.SamAccountName -notin $ExclusionList -and
        -not ($ExcludedOUs | Where-Object { $u.DistinguishedName -like "*$_" })
    } | Sort-Object SamAccountName

$dir = Split-Path $OutputPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$users | Select-Object SamAccountName, Name, @{N='LastLogon';E={[DateTime]::FromFileTime($_.LastLogonTimestamp).ToString("dd.MM.yyyy")}}, DistinguishedName |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "$($users.Count) Benutzer nach $OutputPath exportiert" -ForegroundColor Green
