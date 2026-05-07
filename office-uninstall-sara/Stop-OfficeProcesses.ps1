# Force-kills all running Office, Teams and XPhone processes before uninstallation.
# Run as Part 1 of the Office uninstall sequence.

Get-Process | Where-Object {
    $_.ProcessName -match "outlook|winword|excel|powerpnt|teams|onenote|msaccess|visio|lync|msproject|publisher|MSPUB|XPhoneConnect|XPhoneClient|XPhone"
} | Stop-Process -Force -ErrorAction SilentlyContinue

# Redundant check for edge cases where the regex above may miss process name variants
Get-Process | Where-Object {
    $_.ProcessName -eq "MSPUB" -or
    $_.ProcessName -eq "publisher" -or
    $_.ProcessName -eq "teams" -or
    $_.ProcessName -match "XPhone"
} | Stop-Process -Force -ErrorAction SilentlyContinue

exit 0
