# Entfernt USB-Speichergeraete via pnputil - beim Wiedereinstecken prueft Windows die Policy
# USBSTOR (BOT) + SCSI\DISK&VEN__USB (UAS). Schreibt Log fuer Debug.
$logPath = "$env:SystemRoot\Temp\Clear-USBSTOR-Enum.log"
$log = @()
$log += (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " - Clear gestartet"

$devices = @(Get-PnpDevice | Where-Object {
    $_.InstanceId -like "USBSTOR*" -or
    ($_.InstanceId -like "SCSI\DISK*" -and $_.InstanceId -match "VEN__USB")
})
$log += "Gefunden: $($devices.Count) Geraete"

foreach ($d in $devices) {
    $out = pnputil /remove-device $d.InstanceId 2>&1
    $log += "  $($d.InstanceId): $out"
}
$log | Out-File $logPath -Encoding UTF8 -Force
