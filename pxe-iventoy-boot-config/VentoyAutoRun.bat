@echo off
rem Load NIC driver so iVentoy can mount the ISO via network
for %%f in (X:\$WinPEDriver$\Net\*.inf) do drvload "%%f"
rem Wait for network/DHCP
ping 127.0.0.1 -n 16 >nul
