@echo off
:: PowerShell-Skript als Administrator im Silent-Modus ausf�hren
start powershell -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""C:\EDV\PLAP-Config.ps1""' -Verb RunAs -WindowStyle Hidden}"
exit
