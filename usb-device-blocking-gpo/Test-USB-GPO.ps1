<#
.SYNOPSIS
    Diagnose-Skript fuer USB-GPO. Fuehrt Remote auf dem Test-PC aus (der die GPO hat).
    Prueft ob die Richtlinie korrekt angewendet wird.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = "<TEST-CLIENT>",
    [Parameter(Mandatory = $false)]
    [string]$AllowGroup = "Wechselmedien erlauben",
    [Parameter(Mandatory = $false)]
    [string]$GpoName = "Wechselmedien verweigern",
    [switch]$SkipGpUpdate,
    [Parameter(Mandatory = $false)]
    [string]$OutputFile,
    [switch]$EnableSetupAPILogging,
    [switch]$DisableSetupAPILogging,
    [switch]$RunClearNow
)

$ErrorActionPreference = "Continue"

if ($EnableSetupAPILogging -or $DisableSetupAPILogging) {
    $setupBlock = {
        param($Enable)
        $logKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Setup"
        if (-not (Test-Path $logKey)) { New-Item $logKey -Force | Out-Null }
        if ($Enable) {
            Set-ItemProperty -Path $logKey -Name "LogLevel" -Value 0x00000707 -Type DWord -Force
            "SetupAPI-Logging aktiviert. USB-Stick einstecken, dann Script erneut ausfuehren."
        } else {
            Set-ItemProperty -Path $logKey -Name "LogLevel" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            "SetupAPI-Logging deaktiviert."
        }
    }
    $msg = Invoke-Command -ComputerName $ComputerName -ScriptBlock $setupBlock -ArgumentList $EnableSetupAPILogging
    Write-Host $msg
    exit 0
}

if ($OutputFile) {
    Start-Transcript -Path $OutputFile -Force
    Write-Host "Debug-Ausgabe: $OutputFile"
}

$scriptBlock = {
    $base = "HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
    $output = @()

    $output += "=== 0. DEBUG System ==="
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $output += "Windows: $($os.Caption) Build $($os.BuildNumber) $($os.OSArchitecture)"
    $output += "Computer: $env:COMPUTERNAME"
    $output += ""

    $output += "=== 0b. DEBUG Lokaler Admin? ==="
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $output += "Aktueller Prozess (WinRM) Admin: $isAdmin"
    $loggedIn = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if ($loggedIn) {
        $output += "Eingeloggter User: $loggedIn"
        try {
            $admins = (Get-LocalGroupMember -SID "S-1-5-32-544" -ErrorAction Stop).Name
            $sam = $loggedIn -replace '^.*\\', ''
            $inAdmins = ($admins | ForEach-Object { $_ -replace '^.*\\', '' }) -contains $sam
            $output += "User in lokalen Admins: $inAdmins"
        } catch { $output += "Admin-Check: $_" }
    }
    $output += ""

    $output += "=== 0c. DEBUG Admin-Bypass (AllowOverrides) ==="
    if (Test-Path $base) {
        $allVals = Get-ItemProperty $base -ErrorAction SilentlyContinue
        $overrideProp = $allVals.PSObject.Properties | Where-Object { $_.Name -match "Override" }
        if ($overrideProp) {
            $output += $overrideProp | ForEach-Object { "$($_.Name)=$($_.Value)" }
            if (($overrideProp.Value -eq 1)) { $output += "WARNUNG: Admins bypassen Device Restrictions!" }
        } else {
            $output += "Kein Override-Wert (Admins unterliegen Policy)"
        }
    }
    $output += ""

    $gp = gpresult /scope computer /r 2>&1 | Out-String
    $output += "=== 1. GPO-Status ==="
    if ($gp -match "Wechselmedien verweigern") {
        $output += "GPO 'Wechselmedien verweigern' gefunden"
    } else {
        $output += "GPO nicht in angewendeten Richtlinien"
        $output += ($gp | Select-String "Wechselmedien|Denied" | ForEach-Object { $_.Line })
    }
    $output += ""
    $output += "=== 1b. DEBUG gpresult Computer (vollstaendig) ==="
    $output += $gp
    $output += ""

    $output += "=== 2. Registry Restrictions ==="
    if (Test-Path $base) {
        $props = Get-ItemProperty $base -ErrorAction SilentlyContinue
        $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            $output += "$($_.Name) = $($_.Value)"
        }
        $layered = (Get-ItemProperty $base -Name AllowDenyLayered -ErrorAction SilentlyContinue).AllowDenyLayered
        $denyRem = (Get-ItemProperty $base -Name DenyRemovableDevices -ErrorAction SilentlyContinue).DenyRemovableDevices
        $denyUnspec = (Get-ItemProperty $base -Name DenyUnspecified -ErrorAction SilentlyContinue).DenyUnspecified
        if ($layered -eq 0 -and $denyUnspec -eq 1) {
            $output += "OK: DenyUnspecified=1 - nur Whitelist (AllowDeviceIDs) + AllowDeviceClasses werden installiert"
        } elseif ($layered -eq 1) {
            $output += "WARNUNG: AllowDenyLayered=1 - DenyUnspecified wird IGNORIERT, alle Sticks werden erlaubt! Fix: Fix-AllowDenyLayered.ps1"
        } elseif ($denyUnspec -eq 0) {
            $output += "OK: DenyUnspecified=0 (Option A - Zugriffskontrolle ueber User-Config)"
        }
    } else {
        $output += "Key existiert NICHT - GPO nicht angewendet!"
    }
    $output += ""

    $output += "=== 3. DenyUnspecified (bei Layered=0 relevant) ==="
    $deny = (Get-ItemProperty $base -Name DenyUnspecified -ErrorAction SilentlyContinue).DenyUnspecified
    $output += "DenyUnspecified = $deny"
    $layeredCheck = (Get-ItemProperty $base -Name AllowDenyLayered -ErrorAction SilentlyContinue).AllowDenyLayered
    if ($layeredCheck -eq 0 -and $null -ne $deny -and $deny -eq 0) {
        $output += "OK: DenyUnspecified=0 (Option A)"
    }
    $output += ""

    $output += "=== 4. AllowDeviceIDs (Whitelist) ==="
    $allowEnabled = (Get-ItemProperty $base -Name AllowDeviceIDs -ErrorAction SilentlyContinue).AllowDeviceIDs
    if ($null -eq $allowEnabled -or $allowEnabled -ne 1) {
        $output += "WARNUNG: AllowDeviceIDs=1 fehlt im Restrictions-Key - Whitelist ist DEAKTIVIERT! Fix: Fix-AllowDenyLayered.ps1"
    }
    $allowPath = "$base\AllowDeviceIDs"
    if (Test-Path $allowPath) {
        $vals = Get-ItemProperty $allowPath -ErrorAction SilentlyContinue
        $vals.PSObject.Properties | Where-Object { $_.Name -match "^\d+$" } | Sort-Object { [int]$_.Name } | ForEach-Object {
            $output += "$($_.Name): $($_.Value)"
        }
    } else {
        $output += "Key existiert nicht (Whitelist leer)"
    }
    $output += ""

    $output += "=== 4b. DenyDeviceIDs (USBSTOR blockiert?) ==="
    $denyIds = (Get-ItemProperty $base -Name DenyDeviceIDs -ErrorAction SilentlyContinue).DenyDeviceIDs
    $denyPath = "$base\DenyDeviceIDs"
    if ($null -ne $denyIds -and $denyIds -eq 1 -and (Test-Path $denyPath)) {
        $denyVals = Get-ItemProperty $denyPath -ErrorAction SilentlyContinue
        $denyList = $denyVals.PSObject.Properties | Where-Object { $_.Name -match "^\d+$" } | ForEach-Object { $_.Value }
        $output += "Aktiv: $($denyList -join ', ')"
    } else {
        $output += "Nicht aktiv (kein expliziter Deny)"
    }
    $output += ""

    $output += "=== 5. AllowDeviceClasses ==="
    $classPath = "$base\AllowDeviceClasses"
    if (Test-Path $classPath) {
        $vals = Get-ItemProperty $classPath -ErrorAction SilentlyContinue
        $classProps = $vals.PSObject.Properties | Where-Object { $_.Name -match "^\d+$" } | Sort-Object { [int]$_.Name }
        $output += "$($classProps.Count) Klassen erlaubt:"
        foreach ($p in $classProps) {
            $guid = $p.Value
            $name = if ($guid -match "36fc9e60-c465-11cf-8056-444553540000") { " (USBSTOR - erlaubt alle USB-Sticks!)" }
                    elseif ($guid -match "4d36e967-e325-11ce-bfc1-08002be10318") { " (DiskDrive - Option A)" }
                    elseif ($guid -match "4d36e96f-e325-11ce-bfc1-08002be10318") { " (Mouse)" }
                    elseif ($guid -match "4d36e96b-e325-11ce-bfc1-08002be10318") { " (Keyboard)" }
                    elseif ($guid -match "745a17a0-74d3-11d0-b6fe-00a0c90f57da") { " (HIDClass)" }
                    else { "" }
            $output += "  $($p.Name): $guid$name"
        }
    } else {
        $output += "Key existiert nicht"
    }
    $output += ""
    $output += "=== 5b. DEBUG DiskDrive/Volume in AllowDeviceClasses? ==="
    if (Test-Path $classPath) {
        $allGuids = (Get-ItemProperty $classPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -match "^\d+$" } | ForEach-Object { $_.Value }
        $hasDiskDrive = $allGuids | Where-Object { $_ -match "4d36e967" }
        $hasVolume = $allGuids | Where-Object { $_ -match "71a27cdd" }
        if ($hasDiskDrive) {
            $output += "OK: DiskDrive in AllowDeviceClasses (Option A - Zugriffskontrolle ueber User-Config)"
        } elseif ($hasVolume) {
            $output += "WARNUNG: Volume (71a27cdd) in AllowDeviceClasses - kann Wechselmedien-Zugriff erlauben!"
        } else {
            $output += "DiskDrive/Volume NICHT in AllowDeviceClasses (korrekt)"
        }
    } else {
        $output += "AllowDeviceClasses-Key nicht vorhanden"
    }
    $output += ""

    $output += "=== 6. USB-Storage (Enum) ==="
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR") {
        Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR" | ForEach-Object {
            $t = $_.PSChildName
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object {
                $_.PSChildName -notin @("Device Parameters", "Properties")
            } | ForEach-Object {
                $output += "USBSTOR\$t\$($_.PSChildName)"
            }
        }
    } else {
        $output += "Keine USB-Storage"
    }
    $output += ""
    $output += "=== 6a. DEBUG USB-Storage Geraete + Class-GUID ==="
    $usbDevs = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "USBSTOR*" }
    if ($usbDevs) {
        foreach ($d in $usbDevs) {
            $output += "  $($d.InstanceId) | Class: $($d.Class) | ClassGuid: $($d.ClassGuid)"
        }
    } else {
        $output += "Keine USBSTOR-Geraete (Get-PnpDevice)"
    }
    $output += ""

    $output += "=== 6b. Wechselmedien-Laufwerke (nutzbar?) ==="
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }
    if ($vols) {
        foreach ($v in $vols) {
            $output += "$($v.DriveLetter): $($v.FileSystemLabel) - ZUGRIFF MOEGLICH (Policy greift NICHT!)"
        }
    } else {
        $output += "Keine Wechselmedien mit Laufwerksbuchstaben (blockiert oder nicht eingesteckt)"
    }
    $output += ""

    $output += "=== Hinweis ==="
    $retro = (Get-ItemProperty $base -Name DenyUnspecifiedRetroactive -ErrorAction SilentlyContinue).DenyUnspecifiedRetroactive
    if ($retro -eq 1) {
        $output += "DenyUnspecifiedRetroactive=1: Bereits installierte Geraete werden ebenfalls blockiert."
    } else {
        $output += "Ohne Retroaktiv blockiert DenyUnspecified nur NEUE Installationen."
    }

    $denyAll = $null
    $userSid = $null
    if ($loggedIn) {
        try {
            $userSid = (New-Object System.Security.Principal.NTAccount($loggedIn)).Translate([System.Security.Principal.SecurityIdentifier]).Value
            $userRegPath = "Registry::HKEY_USERS\$userSid\Software\Policies\Microsoft\Windows\RemovableStorageDevices"
            if (Test-Path $userRegPath) {
                $denyAll = (Get-ItemProperty $userRegPath -Name Deny_All -ErrorAction SilentlyContinue).Deny_All
            }
        } catch { }
    }

    $gpUser = gpresult /scope user /r 2>&1 | Out-String

    $logPath = "$env:SystemRoot\inf\setupapi.dev.log"
    $setupAPIOut = @("=== 14. SetupAPI.dev.log (Policy-Debug) ===")
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Tail 500 -ErrorAction SilentlyContinue
        $relevant = $content | Select-String -Pattern "USBSTOR|Restrictions|DenyUnspecified|0xe0000248|ERROR_DEVICE_INSTALL_BLOCKED|DeviceInstall"
        if ($relevant) {
            $setupAPIOut += "Relevante Eintraege:"
            $relevant | ForEach-Object { $setupAPIOut += $_.Line }
        } else {
            $setupAPIOut += "Keine Policy-Eintraege. Letzte 15 Zeilen:"
            $content | Select-Object -Last 15 | ForEach-Object { $setupAPIOut += $_ }
        }
    } else {
        $setupAPIOut += "Log nicht gefunden."
    }

    $clearLogOut = @("=== 15. Clear-Startup Log (letzter Boot) ===")
    $clearLogPath = "$env:SystemRoot\Temp\Clear-USBSTOR-Enum.log"
    if (Test-Path $clearLogPath) {
        $clearContent = Get-Content $clearLogPath -ErrorAction SilentlyContinue
        if ($clearContent) {
            $clearLogOut += $clearContent
        } else {
            $clearLogOut += "Log leer."
        }
    } else {
        $clearLogOut += "Log nicht vorhanden - Clear-Script beim letzten Boot nicht gelaufen oder noch nicht ausgefuehrt."
    }

    return @{
        Output       = ($output -join "`n")
        LoggedInUser = $loggedIn
        DenyAll      = $denyAll
        GpUser       = $gpUser
        SetupAPIAnalysis = $setupAPIOut
        ClearStartupLog = $clearLogOut
    }
}

Write-Host "=== USB-GPO Diagnose (Remote: $ComputerName) ===" -ForegroundColor Cyan
Write-Host ""

try {
    $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ErrorAction Stop
    Write-Host $result.Output
    Write-Host ""
    $result.SetupAPIAnalysis | ForEach-Object { Write-Host $_ }

    Write-Host ""
    Write-Host "=== 7. Sicherheitsgruppe '$AllowGroup' ===" -ForegroundColor Cyan
    $loggedIn = $result.LoggedInUser
    if ($loggedIn) {
        Write-Host "Eingeloggt auf $ComputerName : $loggedIn"
        $sam = $loggedIn -replace '^.*\\', ''
        try {
            $members = Get-ADGroupMember $AllowGroup -Recursive -ErrorAction Stop
            $inGroup = $members.SamAccountName -contains $sam
            if ($inGroup) {
                Write-Host "Benutzer '$sam' ist in der Gruppe." -ForegroundColor Green
            } else {
                Write-Host "Benutzer '$sam' ist NICHT in der Gruppe!" -ForegroundColor Red
                Write-Host "Mitglieder: $($members.SamAccountName -join ', ')"
            }
        } catch {
            Write-Host "Gruppe nicht pruefbar (RSAT AD?): $_"
        }
    } else {
        Write-Host "Kein Benutzer eingeloggt / nicht ermittelt"
    }

    Write-Host ""
    Write-Host "=== 8. User Config (RemovableStorage Deny_All) ===" -ForegroundColor Cyan
    $denyAll = $result.DenyAll
    if ($null -ne $denyAll) {
        if ($denyAll -eq 1) {
            Write-Host "Deny_All = 1 (Zugriff blockiert - Policy greift)" -ForegroundColor Green
        } else {
            Write-Host "Deny_All = $denyAll (sollte 1 sein - Policy greift NICHT!)" -ForegroundColor Red
        }
    } else {
        Write-Host "Kein Deny_All gefunden (Registry-Key nicht vorhanden)" -ForegroundColor Yellow
        Write-Host "Wenn User NICHT in Gruppe: User Config wird nicht angewendet - Problem!"
    }

    Write-Host ""
    Write-Host "=== 9. gpresult User (GPO angewendet?) ===" -ForegroundColor Cyan
    $gpUser = $result.GpUser
    if ($gpUser -match "Wechselmedien verweigern") {
        Write-Host "GPO 'Wechselmedien verweigern' in User-Richtlinien gefunden"
    } else {
        Write-Host "GPO 'Wechselmedien verweigern' NICHT in User-Richtlinien!" -ForegroundColor Red
        $gpUser | Select-String "Wechselmedien|Denied|User" | ForEach-Object { Write-Host $_.Line }
    }

    Write-Host ""
    Write-Host "=== 10. GPO-Delegation (Security Filter) ===" -ForegroundColor Cyan
    try {
        $perms = Get-GPPermission -Name $GpoName -All -ErrorAction Stop
        $allowGroupPerm = $perms | Where-Object { $_.Trustee.Name -eq $AllowGroup }
        if ($allowGroupPerm) {
            $denyApply = $allowGroupPerm | Where-Object { ($_.Permission -eq "GpoApply" -or $_.Permission -eq "GpoCustom") -and $_.Denied -eq $true }
            if ($denyApply) {
                Write-Host "'$AllowGroup' hat Deny Apply Group Policy (korrekt)" -ForegroundColor Green
            } else {
                Write-Host "'$AllowGroup' in Delegation. Get-GPPermission zeigt Deny ggf. nicht - manuell pruefen." -ForegroundColor Yellow
            }
        } else {
            Write-Host "'$AllowGroup' nicht in Delegation - Security Filter fehlt!" -ForegroundColor Red
        }
    } catch {
        Write-Host "Delegation nicht pruefbar: $_"
    }

    Write-Host ""
    Write-Host "=== 11. GPO User Config Status ===" -ForegroundColor Cyan
    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
        Write-Host "GPO-Status: $($gpo.GpoStatus)"
        if ($gpo.GpoStatus -eq "UserSettingsDisabled") {
            Write-Host "User Config ist DEAKTIVIERT!" -ForegroundColor Red
        } elseif ($gpo.GpoStatus -eq "AllSettingsDisabled") {
            Write-Host "GPO komplett deaktiviert!" -ForegroundColor Red
        } else {
            Write-Host "User Config aktiviert" -ForegroundColor Green
        }
    } catch {
        Write-Host "GPO-Status nicht pruefbar: $_"
    }

    Write-Host ""
    Write-Host "=== 12. DEBUG GPO-Link + Computer-OU ===" -ForegroundColor Cyan
    try {
        $comp = Get-ADComputer $ComputerName -Properties CanonicalName, DistinguishedName -ErrorAction Stop
        Write-Host "Computer $ComputerName OU: $($comp.CanonicalName)"
        Write-Host "DN: $($comp.DistinguishedName)"
        $report = Get-GPOReport -Name $GpoName -ReportType Xml -ErrorAction Stop
        if ($report -match "LinksTo|SOMPath") {
            $report -split "`n" | Select-String "SOMPath|LinksTo|Enabled" | ForEach-Object { Write-Host $_.Line }
        }
        $xml = [xml]$report
        $linksTo = $xml.SelectNodes("//LinksTo")
        if ($linksTo) { $linksTo | ForEach-Object { Write-Host "Link: $($_.SOMPath)" } }
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
        if ($gpo.WmiFilter) {
            Write-Host "WMI-Filter: $($gpo.WmiFilter.Name)"
        } else {
            Write-Host "WMI-Filter: keiner"
        }
    } catch {
        Write-Host "AD/GP-Link nicht pruefbar (RSAT?): $_"
    }

    Write-Host ""
    Write-Host "=== 13. DEBUG Manuelle Pruefung ===" -ForegroundColor Cyan
    Write-Host "Auf $ComputerName ausfuehren: rsop.msc oder gpresult /h gpresult.html"
    Write-Host "Policy-Debug: -EnableSetupAPILogging fuer mehr Log-Detail, USB einstecken, Script erneut ausfuehren"
    Write-Host ""
    $result.ClearStartupLog | ForEach-Object { Write-Host $_ }

    # 15b: GPO-Clear-Script vorhanden?
    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
        $startupPath = "\\$($gpo.DomainName)\SYSVOL\$($gpo.DomainName)\Policies\$($gpo.Id)\Machine\Scripts\Startup"
        $clearCmd = Join-Path $startupPath "Clear-USBSTOR-Enum.cmd"
        if (Test-Path $clearCmd) {
            Write-Host "Clear-Script in GPO: vorhanden" -ForegroundColor Green
            if (($result.ClearStartupLog -join "`n") -match "nicht vorhanden") {
                Write-Host "Naechste Schritte: gpupdate /force, Neustart - oder -RunClearNow zum sofortigen Test"
            }
        } else {
            Write-Host "Clear-Script in GPO: NICHT vorhanden - Add-StartupScript-ToGPO.ps1 ausfuehren!" -ForegroundColor Red
        }
    } catch { Write-Host "GPO-Check: $_" }

    if ($RunClearNow) {
        Write-Host ""
        Write-Host "=== RunClearNow: Clear-Script jetzt ausfuehren ===" -ForegroundColor Cyan
        $scriptDir = Split-Path $MyInvocation.MyCommand.Path
        $clearScript = Get-Content "$scriptDir\Clear-USBSTOR-Enum.ps1" -Raw -ErrorAction SilentlyContinue
        if ($clearScript) {
            try {
                Invoke-Command -ComputerName $ComputerName -ScriptBlock ([scriptblock]::Create($clearScript)) -ErrorAction Stop
                Start-Sleep -Seconds 2
                $logContent = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                    $p = "$env:SystemRoot\Temp\Clear-USBSTOR-Enum.log"
                    if (Test-Path $p) { Get-Content $p } else { "Log nicht erstellt" }
                }
                $logContent | ForEach-Object { Write-Host $_ }
            } catch { Write-Host "Fehler: $_" -ForegroundColor Red }
        } else {
            Write-Host "Clear-USBSTOR-Enum.ps1 nicht gefunden in $scriptDir"
        }
    }
} catch {
    Write-Host "Fehler: $_" -ForegroundColor Red
    Write-Host "Pruefen: WinRM aktiv? Test-NetConnection $ComputerName -Port 5985"
    $result = $null
}

if (-not $result) {
    Write-Host ""
    Write-Host "=== Lokale GPO-Pruefungen (Remote nicht erreichbar) ===" -ForegroundColor Cyan
    try {
        $perms = Get-GPPermission -Name $GpoName -All -ErrorAction Stop
        $allowGroupPerm = $perms | Where-Object { $_.Trustee.Name -eq $AllowGroup }
        if ($allowGroupPerm) {
            $denyApply = $allowGroupPerm | Where-Object { ($_.Permission -eq "GpoApply" -or $_.Permission -eq "GpoCustom") -and $_.Denied -eq $true }
            if ($denyApply) {
                Write-Host "'$AllowGroup' hat Deny Apply Group Policy (korrekt)" -ForegroundColor Green
            } else {
                Write-Host "'$AllowGroup' in Delegation" -ForegroundColor Yellow
            }
        } else {
            Write-Host "'$AllowGroup' nicht in Delegation!" -ForegroundColor Red
        }
    } catch { Write-Host "Delegation nicht pruefbar: $_" }
    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
        Write-Host "GPO-Status: $($gpo.GpoStatus)"
    } catch { Write-Host "GPO-Status nicht pruefbar: $_" }
}

Write-Host ""
if (-not $SkipGpUpdate) {
    $gpupdateAntwort = Read-Host "gpupdate /force auf $ComputerName ausfuehren? (J/N)"
} else {
    $gpupdateAntwort = "N"
}
if ($gpupdateAntwort -match "^[JjYy]") {
    try {
        $gpResult = Invoke-Command -ComputerName $ComputerName -ScriptBlock { gpupdate /force } -ErrorAction Stop
        Write-Host $gpResult
    } catch {
        Write-Host "gpupdate fehlgeschlagen: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Ende ===" -ForegroundColor Cyan
if ($OutputFile) { Stop-Transcript }
