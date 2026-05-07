# Sends a popup message to the active user session informing them about the ongoing Win11 upgrade.
# Uses the built-in 'msg' command - requires Messenger service or RDP session.

$query = query session | Where-Object { $_ -match "rdp-tcp#\d+" -or $_ -match "console" } |
                         Where-Object { $_ -match "Aktiv" -or $_ -match "Active" }

if ($query) {
    $username = ($query -split '\s+')[1]
    $message  = "Das Upgrade auf Windows 11 hat begonnen. Ihr Computer wird in den naechsten 1-2 Stunden neu gestartet. Bitte schalten Sie das Geraet nicht aus."
    msg $username /TIME:0 $message
} else {
    Write-Error "No active user session found."
}
