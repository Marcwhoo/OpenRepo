# Teams Meeting Add-in Deinstallation Problem - Tiefenanalyse

## Hauptprobleme identifiziert

### 1. Windows Installer Cache Problem
- **Problem**: Wenn die MSI-Datei nicht mehr im WindowsApps-Ordner existiert, kann Windows Installer nicht deinstallieren
- **Fehler**: "Installation source for this product is not available" (Error 1612)
- **Lösung**: Registry-basierte Bereinigung der Windows Installer Datenbank

### 2. Registry-Eintraege in mehreren Hives
- **Problem**: Das Add-in muss in BEIDEN Registry-Hives (HKLM und HKCU) registriert sein
- **Wichtig**: Bei 32-bit Office auf 64-bit Windows auch unter Wow6432Node
- **Pfade**:
  - HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect
  - HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect (bei 32-bit Office)
  - HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect

### 3. Windows Installer Datenbank Registry-Bereinigung
Wenn MSI-Deinstallation fehlschlaegt, muessen folgende Registry-Stellen bereinigt werden:
- HKEY_CLASSES_ROOT\Installer\Products\[GUID in kryptischem Format]
- HKEY_CLASSES_ROOT\Installer\Components\[GUID in kryptischem Format]
- HKEY_CLASSES_ROOT\Installer\Patches\[GUID in kryptischem Format]
- HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\[GUID]
- HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\[GUID]
- HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\[GUID]

### 4. InstallDate Format
- **Format**: YYYYMMDD (z.B. 20251126 fuer 26.11.2025)
- **Registry**: InstallDate ist ein String-Wert, nicht ein Datum-Objekt

### 5. MSI Installation im User-Context
- **Problem**: MSI-Installationen benoetigen normalerweise Admin-Rechte
- **Workaround**: ALLUSERS=1 oder Installation im System-Context

## Bekannte GUIDs fuer Teams Meeting Add-in
- {0D0C3DF6-8349-4A04-BD82-9BB2D32B5CE5}
- {731F6BAA-A986-45C4-BCF4-724D65C1B15C}

## Empfohlene Loesungsansaetze

### 1. Aggressive Registry-Bereinigung
- Alle Windows Installer Datenbank-Eintraege entfernen
- Sowohl HKLM als auch HKCU bereinigen
- Wow6432Node bei 32-bit Office beachten

### 2. InstallSource Registry reparieren
- InstallSource in InstallProperties auf gueltigen Pfad setzen
- Oder InstallSource loeschen, damit Windows Installer neu sucht

### 3. Beide Registry-Hives setzen
- LoadBehavior muss in HKLM UND HKCU gesetzt werden
- Bei 32-bit Office auch unter Wow6432Node

### 4. Windows Installer Service neu starten
- Nach Registry-Bereinigung Windows Installer Service neu starten
- Ermoeglicht Windows Installer, die Aenderungen zu erkennen

### 5. Mehrfaches Neustarten
- Teams und Outlook mehrfach neu starten (4-5 Zyklen)
- Jeder Zyklus: Teams starten -> warten -> Outlook starten -> warten -> beenden

## Microsoft offizielle Loesung
- UninstallOldTMA.ps1 Skript von Microsoft
- Download: https://aka.ms/uninstallclassicteamsscript
- Benoetigt Teams-Version in $msixDictionary Variable
