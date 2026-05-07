$installPath = "C:\EDV\Office 2016 Professional Plus 64bit German"
Set-Location -Path $installPath
Start-Process -FilePath ".\setup.exe" -Wait -NoNewWindow
Write-Output "Installation abgeschlossen."
