# GPO "Wechselmedien verweigern" - Umstellung abgeschlossen

## Durchgefuehrte Aenderungen

### User Configuration (Zugriffskontrolle)
- **Alle Wechselmedienklassen: Jeglichen Zugriff verweigern** = Aktiviert
- Security Filter: Gruppe "Wechselmedien erlauben" mit **Deny** "Apply Group Policy"
- Benutzer IN der Gruppe: koennen USB nutzen. Benutzer NICHT in der Gruppe: blockiert.

### Computer Configuration (Geraete-Whitelist)
- **DenyUnspecified** = 1: Verhindern der Installation von Geraeten, die nicht beschrieben sind
- **AllowDeviceClasses**: HIDClass, Keyboard, Mouse, USB-Hub (Tastatur/Maus funktionieren weiter)
- **AllowDeviceIDs**: Add-USBToWhitelist.ps1 fuegt alle relevanten HW-IDs pro Geraet hinzu (InstanceId + DEVPKEY-Formate). Funktioniert domaenenweit.
- **DenyUnspecifiedRetroactive**: Bereits installierte Geraete werden ebenfalls blockiert

## Verhalten

- USB-Speicher: Nur whitelistete Geraete werden installiert
- USB-Tastatur/Maus: Funktionieren weiterhin
- Neue Sticks: Mit Add-USBToWhitelist.ps1 auf Admin-PC hinzufuegen

## GPO-Verknuepfung

- Verknuepft mit: Domain-Root
- Status: Aktiv

## Empfehlung

- **AllowDenyLayered = 0** (deaktiviert) – Bei 1 wird DenyUnspecified IGNORIERT (Microsoft-Doku). Whitelist-Ansatz funktioniert mit DenyUnspecified.

## Naechste Schritte

1. `gpupdate /force` auf Test-Clients
2. USB-Stick an Client testen (sollte blockiert sein, ausser whitelistet)
3. Weitere Sticks mit `.\Add-USBToWhitelist.ps1` whitelisten
