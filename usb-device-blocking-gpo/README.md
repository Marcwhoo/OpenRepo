# GPO "Wechselmedien verweigern" - Dokumentation

## Ubersicht

Die Group Policy **"Wechselmedien verweigern"** blockiert USB-Speichergeraete (USB-Sticks, externe Festplatten) an Windows-Domaenen-Clients. Die Einschraenkung erfolgt auf zwei Ebenen:

1. **Computer Config:** Device Installation Restrictions (Whitelist) – nur genehmigte Geraete werden installiert
2. **User Config:** Removable Storage Access – Zugriff auf alle Wechselmedien wird verweigert

**Davon nicht betroffen:** USB-Tastaturen, -Maeuse, USB-Kameras, Mikrofone, Headsets, Drucker, Scanner, Smartcard-Leser

---

## Architektur

### Computer Configuration (Geraete-Whitelist)

| Einstellung | Wert | Bedeutung |
|-------------|------|-----------|
| DenyUnspecified | 0 (Option A) | Aus: Alle Geraete duerfen installieren |
| DenyUnspecifiedRetroactive | 1 | Bereits installierte Geraete werden ebenfalls blockiert |
| AllowDenyLayered | 0 | MUSS 0 sein! Bei 1 wird DenyUnspecified IGNORIERT (Microsoft-Doku) |
| AllowDeviceIDs | Whitelist | Nur diese Hardware-IDs duerfen installiert werden |
| AllowDeviceClasses | 10 Klassen | HIDClass, Keyboard, Mouse, DiskDrive etc. (Option A: Zugriffskontrolle ueber User-Config) |

**Registry:** `HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions`

### User Configuration (Zugriffskontrolle)

| Einstellung | Wert | Bedeutung |
|-------------|------|-----------|
| Alle Wechselmedienklassen: Jeglichen Zugriff verweigern | Aktiviert | Deny_All = 1 in Registry |

**Registry:** `HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices`  
**Pfad:** User Config → Administrative Vorlagen → System → Wechselmedienzugriff

**Wichtig:** User Config gilt nur fuer Benutzer in der OU, an die die GPO verknuepft ist.

### Security Filter (Ausnahme)

**Gruppe:** "Wechselmedien erlauben"  
**Recht:** Deny "Apply Group Policy" auf die GPO

- **Mitglieder:** GPO greift NICHT – USB-Zugriff erlaubt
- **Nicht-Mitglieder:** GPO greift – USB-Zugriff blockiert

---

## Verhalten

| Szenario | Ergebnis |
|----------|----------|
| Normaler Benutzer, USB-Stick | Geraet wird installiert, Zugriff verweigert (Deny_All) |
| Benutzer in "Wechselmedien erlauben" | Alle USB-Sticks funktionieren (GPO greift nicht) |

### Option A: Zugriffskontrolle (aktuell)

- **DiskDrive in AllowDeviceClasses:** Alle USB-Sticks koennen Treiber installieren
- **Deny_All (User-Config):** Zugriff nur fuer User in "Wechselmedien erlauben"
- Keine Hardware-Whitelist noetig – skaliert fuer viele Geraete

---

## GPO-Verknuepfung

- **Verknuepft mit:** Domain-Root
- **Status:** Aktiv (Computer Config + User Config)
- **GPO-Status:** AllSettingsEnabled

---

## Skripte

Alle Skripte im Ordner `usbdeviceblocking\` – auf Admin-PC mit RSAT ausfuehren.

### Add-USBToWhitelist.ps1

Fuegt USB-Geraete zur Whitelist hinzu (nur bei Option B / Hardware-Whitelist relevant).

- **Wo ausfuehren:** Admin-PC (Geraet muss angeschlossen sein)
- **Erkennt:** USBSTOR (BOT) und SCSI (UAS) – funktioniert auch auf Admin-PCs
- **Hardware-ID:** Nur modell-spezifisch (Ven/Prod/Rev). Andere SanDisk-Modelle bleiben blockiert.
- **Parameter:** `-GpoName`, `-WhatIf`

```powershell
.\Add-USBToWhitelist.ps1
```

### Remove-USBFromWhitelist.ps1

Entfernt Geraete aus der Whitelist.

- **Parameter:** `-GpoName`, `-WhatIf`

```powershell
.\Remove-USBFromWhitelist.ps1
```

### Test-USB-GPO.ps1

Diagnose-Skript – prueft Remote per WinRM, ob die GPO korrekt angewendet wird.

- **Parameter:** `-ComputerName`, `-AllowGroup`, `-GpoName`, `-SkipGpUpdate`, `-RunClearNow`, `-OutputFile`, `-EnableSetupAPILogging`, `-DisableSetupAPILogging`
- **Default:** Test-Client (Platzhalter)
- **-RunClearNow:** Clear-Script sofort ausfuehren (ohne Neustart) – prueft ob pnputil /remove-device funktioniert

```powershell
.\Test-USB-GPO.ps1
.\Test-USB-GPO.ps1 -RunClearNow
```

**Voraussetzung:** WinRM auf dem Ziel-PC aktiv (siehe Fix-WinRM-lokal.ps1)

### Fix-AllowDenyLayered.ps1

Setzt AllowDenyLayered=0, DenyUnspecified=1, DenyRemovableDevices=0, AllowDeviceIDs=1. AllowDeviceIDs=1 aktiviert die Whitelist – ohne diesen DWORD werden Whitelist-Eintraege ignoriert. Bei AllowDenyLayered=1 wird DenyUnspecified ignoriert.

```powershell
.\Fix-AllowDenyLayered.ps1
```

### Fix-Scenario5-USB.ps1

Microsoft Scenario 5: DenyDeviceClasses (USB) + AllowDeviceIDs (Infrastruktur + Whitelist). Alternative falls DenyUnspecified nicht greift. USB-Storage nutzt DiskDrive-Klasse – Scenario 5 kann trotzdem nicht alle Sticks blockieren.

```powershell
.\Fix-Scenario5-USB.ps1
```

### Fix-WinRM-lokal.ps1

Aktiviert WinRM auf dem Ziel-PC fuer Remote-Diagnose.

- **Wo ausfuehren:** Auf dem Ziel-PC (RDP oder direkt)
- **Als Administrator ausfuehren**

```powershell
.\Fix-WinRM-lokal.ps1
```

### Clear-USBSTOR-Enum.ps1 / .cmd

Entfernt USB-Speichergeraete via `pnputil /remove-device`. Beim Wiedereinstecken prueft Windows die Device Installation Restrictions.

- **Lokal:** Auf Ziel-PC als Admin ausfuehren
- **Remote:** `.\Test-USB-GPO.ps1 -RunClearNow` oder `.\_run-clear.ps1`

### Add-StartupScript-ToGPO.ps1

Kopiert Clear-USBSTOR-Enum.cmd/.ps1 in die GPO als Startup-Script. Nach Ausfuehrung: gpupdate /force + Neustart auf Clients.

```powershell
.\Add-StartupScript-ToGPO.ps1
```

---

## Voraussetzungen

- **Admin-PC:** RSAT (Group Policy Modul), PowerShell
- **Ziel-PC:** WinRM aktiv (fuer Test-USB-GPO.ps1)
- **Domain:** GPO-Verknuepfung an der richtigen OU

---

## Troubleshooting

1. **USB blockiert, aber Whitelist-Geraet wird angezeigt:** Korrekt – Deny_All blockiert Zugriff. Nur Gruppe "Wechselmedien erlauben" hat Zugriff.

2. **GPO greift nicht:** User in OU? GPO-Status: User Config aktiviert? `gpupdate /force` ausgefuehrt?

3. **gpresult zeigt GPO nicht in User-Richtlinien:** Kann vorkommen. Entscheidend ist `Deny_All = 1` in Registry.

4. **Whitelist-Geraet nicht erkannt:** Hardware-ID pruefen. Nur modell-spezifische IDs (mit Ven/Prod/Rev) verwenden. Generische IDs entfernen – andere Modelle wuerden sonst erlaubt.

5. **WinRM-Fehler bei Test-USB-GPO:** Fix-WinRM-lokal.ps1 auf Ziel-PC als Admin ausfuehren.

6. **USB-Sticks trotzdem nutzbar:** AllowDenyLayered=1? Dann wird DenyUnspecified ignoriert. Fix: Fix-AllowDenyLayered.ps1

7. **Whitelistete Sticks werden nicht erkannt:** DenyRemovableDevices=1 blockiert ALLE Wechselmedien inkl. Whitelist. Fix: Fix-AllowDenyLayered.ps1 (setzt DenyRemovableDevices=0)

8. **AllowDeviceClasses enthaelt USBSTOR:** In GPO manuell entfernen – sonst sind alle USB-Sticks erlaubt.

9. **USB-Sticks trotz GPO nutzbar (bereits installiert):** Windows behandelt bekannte Geraete als Wiederverbindung – Policy greift nicht. Loesung: `Clear-USBSTOR-Enum.ps1` lokal oder `Test-USB-GPO.ps1 -RunClearNow` remote. Beim Wiedereinstecken prueft Windows die Policy.

10. **DenyUnspecified/AllowDeviceClasses greifen nicht:** Device Installation Restrictions sind unter Windows unzuverlaessig. Add-DenyUSBStorage widerspricht den Vorgaben (Whitelist muss funktionieren). Nur DenyUnspecified + AllowDeviceIDs + AllowDeviceClasses verwenden.

11. **Alle USB-Sticks werden erkannt trotz Whitelist:** Bekannte Einschraenkung. Moegliche Ursachen: (a) Inbox-Treiber umgehen Policy, (b) bereits bekannte Geraete (Wiederverbindung) – `Test-USB-GPO.ps1 -RunClearNow` + Neustart, (c) AllowDeviceClasses enthaelt Volume (71a27cdd) oder DiskDrive (4d36e967). Alternative: Fix-Scenario5-USB.ps1 (Microsoft Scenario 5) – blockiert USB-Klassen, kann bei manchen Setups helfen. Ggf. Drittanbieter-Device-Control pruefen.

12. **Abschnitt 15 "Log nicht vorhanden":** Clear-Script beim Boot nicht gelaufen. Pruefen: Test-Script zeigt "Clear-Script in GPO: vorhanden/nicht vorhanden". Wenn nicht vorhanden: Add-StartupScript-ToGPO.ps1 ausfuehren. Wenn vorhanden: gpupdate /force, Neustart. Sofort-Test ohne Neustart: `-RunClearNow`

13. **Whitelist-Stick wird blockiert (0xE0000248):** AllowDeviceIDs=1 fehlt im Restrictions-Key – die Whitelist ist deaktiviert. Fix: Fix-AllowDenyLayered.ps1 ausfuehren, gpupdate /force, Neustart.

---

## E-Mail-Vorlage

Fuer Mitarbeiter-Information siehe `Email-Vorlage-Mitarbeiter-Info.md`.

---

## Referenz: Registry-Pfade

| Komponente | Pfad |
|-----------|------|
| Computer Config (Restrictions) | HKLM\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions |
| AllowDeviceIDs (Whitelist) | HKLM\...\Restrictions\AllowDeviceIDs |
| User Config (Deny_All) | HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices |
