<#
.SYNOPSIS
    Auf dem ZIEL-PC ausfuehren (RDP oder direkt). Aktiviert WinRM fuer Remote-PowerShell.
    WICHTIG: PowerShell als Administrator starten (Rechtsklick -> Als Administrator ausfuehren)
    Danach funktioniert Test-USB-GPO.ps1 von Admin-PC aus.
#>
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Als Administrator ausfuehren! Rechtsklick auf PowerShell -> Als Administrator ausfuehren" -ForegroundColor Red
    exit 1
}
winrm quickconfig -q
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Write-Host "WinRM aktiviert. Test-Skript kann nun von Admin-PC ausgefuehrt werden."