@echo off
cd /d %~dp0
powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; .\UpdateOvpnFiles.ps1"
pause
