# Script zum Entfernen aller Delete-Actions aus der GPO
# Delete-Actions mit negierten Item-Level Targeting Filtern funktionieren nicht zuverlässig

param(
    [Parameter(Mandatory=$false)]
    [string]$GPOName = "Drucker - <PRINT-SERVER-1>-01 - Alle Drucker"
)

Write-Host "=== Entferne Delete-Actions aus GPO ===" -ForegroundColor Cyan
Write-Host "GPO-Name: $GPOName" -ForegroundColor Yellow
Write-Host ""

# Hole GPO
try {
    $gpo = Get-GPO -Name $GPOName -ErrorAction Stop
    Write-Host "GPO gefunden: $($gpo.DisplayName)" -ForegroundColor Green
    Write-Host "GPO-GUID: $($gpo.Id)" -ForegroundColor Gray
} catch {
    Write-Host "[FEHLER] GPO nicht gefunden: $GPOName" -ForegroundColor Red
    exit 1
}

# Pfad zur Printers.xml
$gpoPath = "\\$((Get-ADDomain).DNSRoot)\SYSVOL\$((Get-ADDomain).DNSRoot)\Policies\{$($gpo.Id)}\User\Preferences\Printers"
$printersXmlPath = Join-Path $gpoPath "Printers.xml"

if (-not (Test-Path $printersXmlPath)) {
    Write-Host "[FEHLER] Printers.xml nicht gefunden: $printersXmlPath" -ForegroundColor Red
    exit 1
}

Write-Host "Lade Printers.xml..." -ForegroundColor Yellow
[xml]$printersXml = Get-Content $printersXmlPath -Encoding UTF8

# Zähle Delete-Actions
$deleteActions = $printersXml.SelectNodes("//SharedPrinter[Properties[@action='D']]")
$deleteCount = $deleteActions.Count
Write-Host "Gefunden: $deleteCount Delete-Actions" -ForegroundColor Yellow

if ($deleteCount -eq 0) {
    Write-Host "[INFO] Keine Delete-Actions gefunden. Nichts zu tun." -ForegroundColor Green
    exit 0
}

# Entferne alle Delete-Actions
$removedCount = 0
foreach ($deleteAction in $deleteActions) {
    $printerName = $deleteAction.GetAttribute("name")
    $deleteAction.ParentNode.RemoveChild($deleteAction) | Out-Null
    Write-Host "  [ENTFERNT] $printerName" -ForegroundColor Gray
    $removedCount++
}

# Speichere XML
Write-Host ""
Write-Host "Speichere Printers.xml..." -ForegroundColor Yellow
$printersXml.Save($printersXmlPath)
Write-Host "[OK] Printers.xml gespeichert" -ForegroundColor Green

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "Entfernte Delete-Actions: $removedCount" -ForegroundColor Green
Write-Host ""
Write-Host "HINWEIS: Verwenden Sie das Client-Script '6.4-Client-Entferne-Drucker-nicht-in-Gruppe.ps1'" -ForegroundColor Yellow
Write-Host "        als Scheduled Task, um Drucker zu entfernen, wenn Benutzer nicht mehr in Gruppen sind." -ForegroundColor Yellow
