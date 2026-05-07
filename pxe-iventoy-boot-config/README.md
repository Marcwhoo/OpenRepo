# iVentoy PXE Windows-Installation – Referenz

## Setup-Übersicht

- **iVentoy** als PXE-Server (Windows-Host)
- **Windows 11 Pro ISO** (install.esd, Index 5)
- **Schneegans-Generator** (`PEMode=Generated`) für autounattend.xml
- **Injection via 7z-Archiv** (`autounattend.7z`)

---

## Injection-Archiv (autounattend.7z)

```
autounattend.7z
├── autounattend.xml          # Schneegans-generierte XML (mit iVentoy-Anpassungen)
├── VentoyAutoRun.bat         # Lädt NIC-Treiber vor dem ISO-Mount
└── $WinPEDriver$\
    └── Net\
        ├── *.inf
        ├── *.sys
        ├── *.dll
        └── *.cat
```

In iVentoy Web-Admin: **ISO → Injection File** auf diese 7z setzen.

---

## VentoyAutoRun.bat

Wird von iVentoy automatisch **vor winpeshl.exe** ausgeführt.  
Lädt den NIC-Treiber, damit iVentoy das ISO per HTTP mounten kann.

```batch
@echo off
rem Load NIC driver so iVentoy can mount the ISO via network
for %%f in (X:\$WinPEDriver$\Net\*.inf) do drvload "%%f"
rem Wait for network/DHCP
ping 127.0.0.1 -n 16 >nul
```

---

## Anpassungen in autounattend.xml (vs. Schneegans-Standard)

### 1. ISO-Mount-Warteloop (Order 7 in windowsPE)

iVentoy mountet das ISO als **Y:** erst nach dem Netzwerk-Init.  
Der Schneegans pe.cmd läuft zu früh – daher Warteloop:

```batch
rem Warte bis Y: gemountet ist
:waitloop
if exist Y:\sources\install.esd goto :continue
if exist Y:\sources\install.wim goto :continue
ping 127.0.0.1 -n 6 >nul
goto :waitloop
:continue
```

### 2. autounattend.xml-Fallback (Order 11 in windowsPE)

iVentoy legt die `autounattend.xml` auf `X:\` ab (nicht auf Y:).  
X: ist nicht im Schneegans-Such-Loop – daher expliziter Fallback:

```batch
if not defined XML_FILE if exist X:\autounattend.xml set "XML_FILE=X:\autounattend.xml"
```

### 3. OOBE – HideWirelessSetupInOOBE

Ohne diesen Eintrag erscheint der WLAN-Setup-Screen und blockiert AutoLogon/FirstLogon:

```xml
<OOBE>
    <ProtectYourPC>3</ProtectYourPC>
    <HideEULAPage>true</HideEULAPage>
    <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
    <HideOnlineAccountScreens>false</HideOnlineAccountScreens>
</OOBE>
```

---

## Bekannte Probleme und Lösungen

### httpdisk mount FAILED / KEIN NETZWERK

**Ursache:** NIC-Treiber fehlt im Windows-ISO-WinPE.  
**Lösung:** Treiber (INF/SYS/DLL/CAT) in `$WinPEDriver$\Net\` in die 7z packen.  
**Prüfen:**
```batch
ipconfig /all
ping <iVentoy-Server-IP>
```

### Could not locate install.wim / install.esd

**Ursache:** Y: noch nicht gemountet wenn pe.cmd läuft.  
**Lösung:** Warteloop in Order 7 (siehe oben).  
**Debug:**
```batch
wmic logicaldisk get name
dir Y:\sources\
for %d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do @if exist %d:\sources\install.esd (echo %d:\sources\install.esd)
```

### Could not locate autounattend.xml

**Ursache:** autounattend.xml liegt auf X:\, aber X: ist nicht im Such-Loop.  
**Lösung:** Fallback in Order 11 (siehe oben).  
**Debug:**
```batch
dir X:\autounattend.xml
reg query HKLM\System\Setup /v UnattendFile
```

### WLAN-Screen erscheint / AutoLogon funktioniert nicht

**Ursache:** `HideWirelessSetupInOOBE` fehlt in OOBE.  
**Lösung:** Eintrag in OOBE hinzufügen (siehe oben).

### Verzerrtes Bild (vertikal gestaucht)

**Ursache:** Bekannter iVentoy-Bug (UEFI-GOP-Handoff), seit 2023 offen.  
**Workarounds:**
- Boot Menu Resolution in iVentoy Web-Admin anpassen (native Auflösung des Monitors testen)
- Legacy/BIOS-Boot statt UEFI (CSM aktivieren)
- Verzerrung ignorieren – Installation läuft trotzdem durch (autounattend)

### WIMBOOT (W / Strg+W) reagiert nicht

**Ursache:** WIMBOOT-Tastenkürzel gilt für **Ventoy USB**, nicht für iVentoy PXE.  
`_VTWIMBOOT`-Umbenennung ebenfalls nur für Ventoy USB.

---

## Debug-Befehle im WinPE (Shift+F10)

```batch
# Alle Laufwerke
wmic logicaldisk get name,description

# install.esd/wim suchen
for %d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do @if exist %d:\sources\install.esd (echo %d:\sources\install.esd)

# Netzwerk
ipconfig /all

# iVentoy Mount-Log
type X:\Windows\System32\ventoy\vtoype.log

# VentoyAutoRun-Log
type X:\VentoyAutoRun.log

# Treiber manuell laden
for %f in (X:\$WinPEDriver$\Net\*.inf) do drvload "%f"

# Registry UnattendFile
reg query HKLM\System\Setup /v UnattendFile
```

---

## iVentoy-Ports (Firewall)

| Port | Protokoll | Zweck |
|------|-----------|-------|
| 16000 | TCP | HTTPDisk – ISO-Mount |
| 10809 | TCP | NBD-Server |
| 26000 | TCP | Web-Admin |
| 69 | UDP | TFTP |
| 67/68 | UDP | DHCP |

---

## Wichtige Pfade im WinPE

| Pfad | Inhalt |
|------|--------|
| `X:\autounattend.xml` | Injizierte XML |
| `X:\$WinPEDriver$\Net\` | Injizierte NIC-Treiber |
| `X:\VentoyAutoRun.bat` | Auto-Skript vor winpeshl.exe |
| `X:\VentoyAutoRun.log` | Log von VentoyAutoRun.bat |
| `X:\Windows\System32\ventoy\vtoype.log` | iVentoy Mount-Log |
| `Y:\sources\install.esd` | Windows-Image (nach Mount) |
| `W:\` | Ziel-Partition (Windows) |
| `S:\` | EFI-Partition |

---

## Schneegans-Generator URL

Die aktuelle Konfiguration ist als URL im Kommentar der `autounattend.xml` hinterlegt.  
Zum Regenerieren: URL aus dem XML-Kommentar kopieren und in `https://schneegans.de/windows/unattend-generator/` einfügen.  
**Danach** die iVentoy-Anpassungen (Warteloop, XML-Fallback, OOBE) manuell wieder einbauen.

---

## Auf keinen Fall

- **autounattend.xml nicht direkt bearbeiten** für Schneegans-Features (User, Domain, etc.) – nur über Schneegans-Generator. Die iVentoy-Anpassungen (Warteloop, XML-Fallback, OOBE) sind Ausnahmen und müssen manuell ergänzt werden.
- **Kein Debug-Logging** (RunSynchronous mit Netzwerk-Share, FirstLogon mit Log-Kopieren) in die XML einbauen – macht die XML unbrauchbar.
- **Nicht `timeout`** in pe.cmd verwenden – in WinPE nicht vorhanden. Stattdessen: `ping 127.0.0.1 -n 16 >nul`.
- **Nicht VTOYMNT.BAT / VTOYPE.BAT** aus pe.cmd aufrufen – bei Standard-Windows-ISO falscher Ansatz. Stattdessen: VentoyAutoRun.bat für Treiber, iVentoy mountet automatisch auf Y:.
- **Nicht annehmen**, dass install.esd auf X: liegt – X:\sources\ enthält sie nicht. Nach Mount liegt sie auf Y:\sources\.
