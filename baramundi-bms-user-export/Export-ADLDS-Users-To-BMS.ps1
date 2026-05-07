#Requires -Module ActiveDirectory
# Exports all users from AD LDS to CSV format for BMS import.
# Splits output into two files (part1/part2) to stay within BMS import size limits.
# Run as: baramundi job on the AD LDS server (localhost:3890)

Import-Module ActiveDirectory

$users = Get-ADUser -Server localhost:3890 -SearchBase "dc=<ADLDS-DOMAIN>,dc=<TLD>" -Filter * `
    -Properties givenName,sn,sAMAccountName,departmentNumber,title,mail,objectSid,personalTitle,telephoneNumber,mobile,ipPhone,manager,DistinguishedName `
    -ResultSetSize $null -ResultPageSize 1000

# Group users by OU for departmentNumber fallback logic
$ouGroups = $users | Group-Object { $_.DistinguishedName -replace '^CN=[^,]+,(.*)$', '$1' }

$header = "FirstName;LastName;LoginName;OrgUnit_Customer-Nr;MainLocation_Title;EMail;Preferred_Contact_Type;SSP_Access;Authentication_Type;Windows_Domain;AD_SID;Salutation;Phone;MobilePhone;AcademicTitle;InternalNumber;JobTitle;BudgetLimit;Language;Supervisor_LoginName;Internal_Information;CostCenter;CostCenter_Customer-Nr;Fax;VIP;Additional_EMail;Approval_Never_Required"

$skipUsers = @()  # Add IT service accounts to exclude from export

$lines = New-Object System.Collections.ArrayList

foreach ($user in $users) {
    if ($skipUsers -contains $user.sAMAccountName.ToLower()) { continue }

    # If departmentNumber is empty, fall back to most common value in same OU
    $deptNumber = if ($user.departmentNumber) { $user.departmentNumber -join "," } else { "" }
    $ou = $user.DistinguishedName -replace '^CN=[^,]+,(.*)$', '$1'
    $ouGroup = $ouGroups | Where-Object { $_.Name -eq $ou }
    $commonDeptNumber = $ouGroup.Group | Where-Object { $_.departmentNumber -ne $null } | Group-Object departmentNumber | Sort-Object Count -Descending | Select-Object -First 1 -ExpandProperty Name
    if (-not $deptNumber -and $commonDeptNumber) { $deptNumber = $commonDeptNumber }

    # Skip users missing mandatory fields
    if (-not $user.givenName -or -not $user.sn -or -not $user.sAMAccountName -or -not $deptNumber -or -not $user.mail) { continue }

    # Extract supervisor login from manager DN
    $supervisorLogin = ""
    if ($user.manager) {
        $supervisorUser = Get-ADUser -Identity $user.manager -Server localhost:3890 -Properties sAMAccountName
        if ($supervisorUser) { $supervisorLogin = $supervisorUser.sAMAccountName }
    }

    $sid = ""
    if ($user.objectSid) { $sid = (New-Object System.Security.Principal.SecurityIdentifier $user.objectSid).Value }

    # academicTitle is always empty - not in AD LDS schema
    $academicTitle = ""
    $personalTitle = if ($user.personalTitle) { $user.personalTitle -join "," } else { "" }
    $ipPhone = if ($user.ipPhone) { $user.ipPhone -join "," } else { "" }

    $line = @(
        $user.givenName,
        $user.sn,
        $user.sAMAccountName,
        $deptNumber,
        "Standard",         # MainLocation_Title - adjust per site
        $user.mail,
        "E-Mail",
        "Zugang erteilt",
        "Windows",
        "<DOMAIN-NETBIOS>",
        $sid,
        $personalTitle,
        $user.telephoneNumber,
        $user.mobile,
        $academicTitle,
        $ipPhone,
        "",  # JobTitle
        "",  # BudgetLimit
        "",  # Language
        $supervisorLogin,
        "",  # Internal_Information
        "",  # CostCenter
        "",  # CostCenter_Customer-Nr
        "",  # Fax
        "FALSE",  # VIP
        "",  # Additional_EMail
        ""   # Approval_Never_Required
    ) -join ";"
    $lines.Add($line) | Out-Null
}

# Split into two halves to respect BMS import size limits
$half = [math]::Ceiling($lines.Count / 2)

$csv1 = New-Object System.Collections.ArrayList
$csv1.Add($header) | Out-Null
$csv1.AddRange($lines[0..($half - 1)]) | Out-Null
$csv1 | Out-File -FilePath "C:\userexport_part1.csv" -Encoding UTF8

$csv2 = New-Object System.Collections.ArrayList
$csv2.Add($header) | Out-Null
$csv2.AddRange($lines[$half..($lines.Count - 1)]) | Out-Null
$csv2 | Out-File -FilePath "C:\userexport_part2.csv" -Encoding UTF8
