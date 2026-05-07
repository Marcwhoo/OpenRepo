# ==================================================================
# Batch-Export: AD Vorgesetzte - einheitliche Namensgebung
# ==================================================================
# Zuverlaessiger Ansatz:
# - ASCII-only Dateinamen (keine Umlaute im Script)
# - Call-Operator & fuer synchrone Ausfuehrung
# - Explizite Pfade mit $PSScriptRoot
#
# Das Array $configs unten ist bewusst leer: Die Originalversion
# enthielt organisationsspezifische Bereichsnamen und die sAMAccount-
# Namen der jeweiligen Vorgesetzten als Platzhalter sind Pflichtfeld
# - konkrete Listen gehoeren nicht in ein oeffentliches Repo.
# ==================================================================

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Export-AD-Employees-By-Supervisor.ps1"
$outDir = "c:\edv"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Export-Script nicht gefunden: $scriptPath"
    exit 1
}

# Beispiel-Struktur. Passe <BEREICH-N> und die sAMAccountNames an.
$configs = @(
    @{ Name = "<BEREICH-1>"; Vorgesetzte = @("<SAMACCOUNTNAME-1>", "<SAMACCOUNTNAME-2>") }
    # @{ Name = "<BEREICH-2>"; Vorgesetzte = @("<SAMACCOUNTNAME-3>", "<SAMACCOUNTNAME-4>") }
)

$fileNameBase = "AD Vorgesetzte - "

foreach ($cfg in $configs) {
    $fileName = $fileNameBase + $cfg.Name
    Write-Host "Export: $fileName" -ForegroundColor Cyan
    & $scriptPath -VorgesetzteListe $cfg.Vorgesetzte -OutputDirectory $outDir -OutputFileName $fileName
}

Write-Host "`nFertig. Dateien in $outDir" -ForegroundColor Green
Get-ChildItem -Path $outDir -Filter "AD Vorgesetzte - *.csv" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime
