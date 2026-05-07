# GPO "Wechselmedien verweigern" - Vollstaendige Evaluation

## 1. GPO-Komponenten Ueberblick

| Komponente | Typ | Status | Zweck |
|------------|-----|--------|-------|
| Device Installation Restrictions | Computer Config | Aktiv | Whitelist: Nur AllowDeviceIDs + AllowDeviceClasses installieren |
| DenyUnspecified | Registry | 1 | Blockiert Geraete nicht in Allow-Listen |
| AllowDeviceIDs | Registry | Leer (Whitelist entfernt) | Whitelist Hardware-IDs |
| AllowDeviceClasses | Registry | 9 Klassen | HIDClass, Keyboard, Mouse, Camera, etc. |
| Removable Storage Deny_All | User Config | Aktiv | Zugriff auf Wechselmedien blockieren |
| Security Filter | Delegation | "Wechselmedien erlauben" Deny Apply | Ausnahme: Gruppenmitglieder bekommen GPO nicht |
| Clear-USBSTOR-Enum | Startup Script | In GPO | Entfernt USB-Speicher bei Boot |

---

## 2. Clear-Script: Wann und was passiert

### Ablauf
- **Wann:** Beim Computer-Start (nach GPO-Apply, vor User-Login)
- **Wo:** `\\domain\SYSVOL\...\Policies\{GUID}\Machine\Scripts\Startup\`
- **Aufruf:** scripts.ini -> Clear-USBSTOR-Enum.cmd -> Clear-USBSTOR-Enum.ps1

### Was pnputil /remove-device macht
- **Wichtig:** Funktioniert auch fuer **getrennte/ghost** Geraete (Microsoft-Doku)
- Entfernt Device aus PnP-Baum und bereinigt Registry (Enum-Eintraege)
- Get-PnpDevice **ohne** -PresentOnly liefert alle Geraete inkl. nicht verbundene

### Konsequenz
Clear beim Startup **kann** bekannte USB-Geraete bereinigen – auch wenn beim Boot nichts eingesteckt ist. Beim naechsten Einstecken wird das Geraet neu evaluiert.

---

## 3. Warum die Whitelist trotzdem nicht greift

### Beobachtung aus SetupAPI-Log
- "Previously blocked device is now allowed by policy" (nach Whitelist-Entfernung)
- "Device Removal Initiated by Policy Change" – Policy loest Entfernung aus
- "Unable to re-enumerate blocked device" (0x00000490) – Re-Enumeration schlaegt fehl

### Moegliche Ursachen (nicht abschliessend)

1. **Leerer AllowDeviceIDs-Key:** Wenn der Key fehlt oder leer ist, wird die Whitelist-Logik moeglicherweise nicht angewendet – Verhalten dann "allow all".

2. **Reihenfolge/Zeitpunkt:** Clear laeuft beim Boot. Wenn beim Boot keine USB-Geraete im System sind, liefert Get-PnpDevice ggf. keine Treffer. Zu pruefen: Liefert Get-PnpDevice ohne -PresentOnly beim Boot ueberhaupt USBSTOR-Eintraege?

3. **GPO-Verknuepfung:** GPO haengt an Domain-Root oder OU. Liegen alle 2000 Rechner in der verknuepften OU? Wenn nicht, bekommen manche den Startup nicht.

4. **SYSVOL-Pfad:** scripts.ini verweist auf `Clear-USBSTOR-Enum.cmd`. Muss nach Add-StartupScript-ToGPO.ps1 .cmd und .ps1 im Startup-Ordner liegen. Nach GPO-Aenderungen: Wurde Add-StartupScript-ToGPO.ps1 erneut ausgefuehrt?

5. **ExecutionPolicy:** .cmd ruft PowerShell mit -ExecutionPolicy Bypass auf – sollte unkritisch sein.

---

## 4. Konflikte / Widersprueche

| Aspekt | Potenzieller Konflikt |
|--------|------------------------|
| Whitelist leer | Ohne AllowDeviceIDs: Unklar ob DenyUnspecified wie erwartet greift |
| Clear + Whitelist | Clear bereinigt, Whitelist soll blockieren – theoretisch sinnvoll, praktisch unzuverlaessig |
| User Config | Gilt nur fuer User in der OU der GPO-Verknuepfung. Bei Verknuepfung an Computer-OU: User Config wird ueber Computer-OU ermittelt |

---

## 5. Was konkret zu prufen ist

1. **Startup-Script auf Client:** Auf einem Test-PC pruefen:
   - Existiert `\\<DOMAIN-FQDN>\SYSVOL\<DOMAIN-FQDN>\Policies\{<GPO-GUID>}\Machine\Scripts\Startup\`?
   - Enthaelt es Clear-USBSTOR-Enum.cmd und Clear-USBSTOR-Enum.ps1?
   - Enthaelt scripts.ini den Eintrag fuer Clear-USBSTOR-Enum.cmd?

2. **Clear beim Boot:** Nach Neustart eines Test-PCs mit eingestecktem USB-Stick:
   - Wird der Stick entfernt (verschwindet Laufwerk)?
   - Oder: Nach Boot ohne Stick – liefert `Get-PnpDevice | Where-Object { $_.InstanceId -like "USBSTOR*" }` Eintraege? (lokal auf Test-PC ausfuehren)

3. **Whitelist wieder aktivieren:** SanDisk zur Whitelist zurueck, dann:
   - Clear manuell ausfuehren (_run-clear.ps1)
   - Alle Sticks abziehen, Neustart
   - Nur Whitelist-Stick einstecken – wird er erkannt?
   - Nicht-Whitelist-Stick einstecken – wird er blockiert?

4. **GPO-Verknuepfung:** `Get-GPOReport -Name "Wechselmedien verweigern" -ReportType Xml` – welche OUs sind verknuepft? Liegt der Test-Client (und die anderen Rechner) darunter?

---

## 6. Empfehlung (ohne Garantie)

### Option A: Nur Zugriffskontrolle (stabil)
- DenyUnspecified=0 setzen (Device Installation deaktivieren)
- Whitelist nicht nutzen
- Nur Deny_All + Security Filter "Wechselmedien erlauben"
- Clear-Script aus Startup entfernen (nicht noetig)

### Option B: Whitelist weiter versuchen
- Whitelist wieder befuellen (Add-USBToWhitelist.ps1)
- Auf Test-PC: Punkte 1–3 aus Abschnitt 5 durchgehen
- Wenn Clear beim Boot keine USBSTOR-Eintraege findet: Get-PnpDevice ohne -PresentOnly testen
- Wenn Whitelist nach Clear + Neustart + neuem Stick funktioniert: Schrittweise auf weitere PCs ausrollen

### Option C: Baramundi Device Control
- Wenn GPO-Whitelist nicht zuverlaessig funktioniert: Device Control (DriveLock) evaluieren

---

## 7. Offene Punkte

- Verifizieren, ob Get-PnpDevice beim Boot (ohne User) USBSTOR-Eintraege fuer getrennte Geraete liefert
- Klaren, ob leerer AllowDeviceIDs-Key "allow all" bedeutet
- Testen, ob Clear + Whitelist auf einem frischen/bereinigten Test-PC funktioniert
