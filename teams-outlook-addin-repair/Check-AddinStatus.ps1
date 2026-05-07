# Quick Check - Teams Add-in Status remote auslesen
# Ausfuehren: .\Check-AddinStatus.ps1 -ComputerName "<CLIENT-HOSTNAME>"

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

Write-Host "=== Teams Add-in Status Check: $ComputerName ===" -ForegroundColor Cyan

$result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    $status = @{}
    
    # 1. Add-in Registry (HKCU)
    $addinPath = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
    if (Test-Path $addinPath) {
        $props = Get-ItemProperty $addinPath -EA SilentlyContinue
        $status.AddinRegistry = @{
            Exists = $true
            LoadBehavior = $props.LoadBehavior
            FriendlyName = $props.FriendlyName
            Manifest = $props.Manifest
        }
    } else {
        $status.AddinRegistry = @{ Exists = $false }
    }
    
    # 2. Add-in DLL
    $dllPaths = @(
        "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAdd-in\x64\Microsoft.Teams.AddinLoader.dll",
        "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin\x64\Microsoft.Teams.AddinLoader.dll"
    )
    $status.DLL = @{ Exists = $false; Path = $null }
    foreach ($p in $dllPaths) {
        if (Test-Path $p) {
            $status.DLL = @{ Exists = $true; Path = $p }
            break
        }
    }
    
    # 3. COM Registration (HKCU)
    $clsids = @(
        "HKCU:\Software\Classes\CLSID\{0E4CB80D-CF87-4E1B-B113-5D5D5E7DA021}",
        "HKCU:\Software\Classes\CLSID\{16F0BF0C-D1E5-4F76-95C8-36E7DCA9E76E}"
    )
    $status.COMRegistration = @{ Found = $false; Paths = @() }
    foreach ($c in $clsids) {
        if (Test-Path $c) {
            $status.COMRegistration.Found = $true
            $status.COMRegistration.Paths += $c
        }
    }
    
    # 4. RegisterAsOfficeChatApp
    $teamsPath = "HKCU:\Software\Microsoft\Office\Teams"
    if (Test-Path $teamsPath) {
        $props = Get-ItemProperty $teamsPath -EA SilentlyContinue
        $status.RegisterAsOfficeChatApp = $props.RegisterAsOfficeChatApp
    } else {
        $status.RegisterAsOfficeChatApp = $null
    }
    
    # 5. DisabledItems Check
    $resiliencyPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems"
    $status.DisabledItems = @()
    if (Test-Path $resiliencyPath) {
        Get-ItemProperty $resiliencyPath -EA SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
            if ($_.Name -notlike "PS*") {
                $status.DisabledItems += $_.Name
            }
        }
    }
    
    # 6. DoNotDisableAddinList
    $doNotDisablePath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"
    if (Test-Path $doNotDisablePath) {
        $props = Get-ItemProperty $doNotDisablePath -EA SilentlyContinue
        $status.DoNotDisable = $props.'TeamsAddin.FastConnect'
    } else {
        $status.DoNotDisable = $null
    }
    
    return $status
}

Write-Host ""
Write-Host "1. Add-in Registry (TeamsAddin.FastConnect):" -ForegroundColor Yellow
if ($result.AddinRegistry.Exists) {
    Write-Host "   Existiert: JA" -ForegroundColor Green
    Write-Host "   LoadBehavior: $($result.AddinRegistry.LoadBehavior)" $(if($result.AddinRegistry.LoadBehavior -eq 3){"(OK)"}else{"(FALSCH - sollte 3 sein)"})
    Write-Host "   FriendlyName: $($result.AddinRegistry.FriendlyName)"
    Write-Host "   Manifest: $($result.AddinRegistry.Manifest)" $(if($result.AddinRegistry.Manifest){"(WARNUNG: sollte leer sein!)"}else{"(OK - leer)"})
} else {
    Write-Host "   Existiert: NEIN" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Add-in DLL:" -ForegroundColor Yellow
if ($result.DLL.Exists) {
    Write-Host "   Existiert: JA" -ForegroundColor Green
    Write-Host "   Pfad: $($result.DLL.Path)"
} else {
    Write-Host "   Existiert: NEIN" -ForegroundColor Red
}

Write-Host ""
Write-Host "3. COM Registration:" -ForegroundColor Yellow
if ($result.COMRegistration.Found) {
    Write-Host "   Gefunden: JA" -ForegroundColor Green
    $result.COMRegistration.Paths | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   Gefunden: NEIN" -ForegroundColor Red
}

Write-Host ""
Write-Host "4. RegisterAsOfficeChatApp:" -ForegroundColor Yellow
Write-Host "   Wert: $($result.RegisterAsOfficeChatApp)" $(if($result.RegisterAsOfficeChatApp -eq 1){"(OK)"}else{"(sollte 1 sein)"})

Write-Host ""
Write-Host "5. DisabledItems:" -ForegroundColor Yellow
if ($result.DisabledItems.Count -gt 0) {
    Write-Host "   WARNUNG: Add-in koennte deaktiviert sein!" -ForegroundColor Red
    $result.DisabledItems | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   Keine (OK)" -ForegroundColor Green
}

Write-Host ""
Write-Host "6. DoNotDisableAddinList:" -ForegroundColor Yellow
Write-Host "   TeamsAddin.FastConnect: $($result.DoNotDisable)" $(if($result.DoNotDisable -eq 1){"(OK)"}else{"(sollte 1 sein)"})

Write-Host ""
Write-Host "=== Check abgeschlossen ===" -ForegroundColor Cyan
