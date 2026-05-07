# Entfernt USB-Speichergeraete via pnputil - beim Wiedereinstecken prueft Windows die Policy
$scriptBlock = {
    $removed = 0
    Get-PnpDevice | Where-Object { $_.InstanceId -like "USBSTOR*" } | ForEach-Object {
        pnputil /remove-device $_.InstanceId 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $removed++ }
    }
    "Entfernt: $removed Geraete. Beim Wiedereinstecken wird Policy geprueft."
}
Invoke-Command -ComputerName <TEST-CLIENT> -ScriptBlock $scriptBlock
