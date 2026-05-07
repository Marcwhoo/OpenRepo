@echo off
:: Erstelle eine geplante Aufgabe mit SYSTEM-Rechten fuer den Registry-Import
schtasks /create /tn "PLAP-Registry-Fix" /tr "cmd /c reg import \"C:\Program Files\OpenVPN\bin\openvpn-plap-install.reg\"" /sc once /st 00:00 /ru SYSTEM /f

:: Starte die geplante Aufgabe sofort
schtasks /run /tn "PLAP-Registry-Fix"

:: Warte 5 Sekunden, damit das Skript ausgefuehrt wird
timeout /t 5 /nobreak >nul

:: Loesche die geplante Aufgabe nach der Ausfuehrung
schtasks /delete /tn "PLAP-Registry-Fix" /f
exit

