# DNS Scavenging - Erklärung und Empfehlung

## Was ist DNS Scavenging?

**DNS Scavenging** ist ein automatischer Prozess, der veraltete DNS-Records aus der Zone entfernt. 

### Wie funktioniert es?

1. **Aging (Alterung):**
   - Jeder DNS-Record bekommt einen "Timestamp" (Zeitstempel) wenn er erstellt oder aktualisiert wird
   - Der Record wird als "veraltet" markiert, wenn er länger als die "No-Refresh-Interval" + "Refresh-Interval" Zeit nicht aktualisiert wurde

2. **Scavenging (Bereinigung):**
   - Der DNS-Server durchsucht regelmäßig die Zone nach veralteten Records
   - Records, die länger als das "Scavenging-Interval" veraltet sind, werden automatisch gelöscht

### Standard-Intervalle:

- **No-Refresh-Interval:** 7 Tage (168 Stunden)
  - In dieser Zeit wird der Timestamp NICHT aktualisiert, auch wenn der Record verwendet wird
  - Verhindert unnötige Replikation bei jedem Zugriff

- **Refresh-Interval:** 7 Tage (168 Stunden)
  - Nach diesem Intervall kann der Timestamp wieder aktualisiert werden
  - Wenn der Record verwendet wird, wird der Timestamp aktualisiert

- **Scavenging-Interval:** 7 Tage (168 Stunden)
  - Wie oft der Scavenging-Prozess läuft
  - Records, die länger als (No-Refresh + Refresh) = 14 Tage veraltet sind, werden gelöscht

**Total:** Ein Record wird gelöscht, wenn er **14 Tage lang nicht verwendet** wurde.

---

## Aktuelle Situation in Ihrer Umgebung

**Status:** Scavenging ist **DEAKTIVIERT**

**Zone-Größe:**
- <DOMAIN-FQDN>: **1670 Records** (sehr groß!)
- DC01: 1670 Records
- DC02: 1672 Records (2 Records Unterschied)

**Problem:**
- Alte, nicht mehr verwendete Records bleiben in der Zone
- Zone wird immer größer
- Langfristig kann das zu Performance-Problemen führen

---

## Sollten Sie Scavenging aktivieren?

### ✅ **JA, aber vorsichtig!**

### Vorteile:

1. **Automatische Bereinigung:**
   - Entfernt alte, nicht mehr verwendete Records automatisch
   - Reduziert Zone-Größe langfristig
   - Bessere Performance bei großen Zonen

2. **Weniger manuelle Arbeit:**
   - Keine manuelle Bereinigung nötig
   - Reduziert Fehler bei manueller Bereinigung

3. **Konsistenz:**
   - Alle Records haben Timestamps
   - Bessere Nachverfolgbarkeit

### ⚠️ **Risiken und Probleme:**

1. **Aktive Records könnten gelöscht werden:**
   - Wenn ein Server 14+ Tage offline ist (Wartung, Urlaub, etc.)
   - Der DNS-Record wird gelöscht, auch wenn der Server noch existiert
   - **Problem:** Server ist nach Wartung nicht mehr per DNS erreichbar

2. **Statische Records ohne Timestamps:**
   - Manuell erstellte Records haben oft keine Timestamps
   - Werden sofort als "veraltet" markiert
   - Können nach 14 Tagen gelöscht werden, auch wenn sie noch benötigt werden

3. **DHCP-Client-Records:**
   - DHCP-Clients aktualisieren ihre Records automatisch
   - Aber: Wenn ein Client 14+ Tage offline ist, wird der Record gelöscht
   - **Problem:** Client ist nach längerer Abwesenheit nicht mehr per DNS erreichbar

4. **Kritische Server:**
   - Server, die selten verwendet werden, aber wichtig sind
   - Können versehentlich gelöscht werden

---

## Empfehlung für Ihre Umgebung

### **Option 1: Scavenging aktivieren (EMPFOHLEN, aber vorsichtig)**

**Schritte:**

1. **Vorbereitung (WICHTIG!):**
   - Alle wichtigen Records mit Timestamps versehen
   - Statische Records manuell aktualisieren (Timestamp setzen)
   - Testen auf einer Test-Zone zuerst

2. **Konfiguration:**
   - No-Refresh-Interval: **7 Tage** (Standard)
   - Refresh-Interval: **7 Tage** (Standard)
   - Scavenging-Interval: **7 Tage** (Standard)
   - **Total:** Records werden nach **14 Tagen Inaktivität** gelöscht

3. **Überwachung:**
   - Erste Wochen genau beobachten
   - Prüfen, welche Records gelöscht werden
   - Bei Problemen sofort deaktivieren

### **Option 2: Scavenging NICHT aktivieren (KONSERVATIV)**

**Wenn:**
- Viele Server selten verwendet werden (z.B. nur bei Wartung)
- Viele statische Records ohne Timestamps vorhanden sind
- Keine Zeit für sorgfältige Vorbereitung vorhanden ist

**Alternative:**
- Manuelle Bereinigung 1-2x pro Jahr
- Scripts zur Identifikation alter Records

---

## Konkrete Empfehlung für Sie

### **Empfehlung: Scavenging aktivieren, aber mit längeren Intervallen**

**Konfiguration:**
- No-Refresh-Interval: **14 Tage** (länger als Standard)
- Refresh-Interval: **14 Tage** (länger als Standard)
- Scavenging-Interval: **7 Tage**
- **Total:** Records werden nach **28 Tagen Inaktivität** gelöscht

**Vorteile:**
- Reduziert Risiko, dass aktive Server gelöscht werden
- Gibt mehr Zeit für Wartungen
- Bereinigt trotzdem alte Records

**Vorbereitung:**
1. Alle wichtigen Records prüfen und ggf. Timestamps setzen
2. Statische Records identifizieren und dokumentieren
3. Testen auf einer Test-Zone
4. Monitoring für erste 4 Wochen einrichten

---

## Scripts zur Vorbereitung

Ich kann Scripts erstellen für:
1. **DNS-Records-Analyse:** Zeigt alle Records ohne Timestamps
2. **Scavenging-Konfiguration:** Aktiviert Scavenging mit sicheren Einstellungen
3. **Scavenging-Monitoring:** Überwacht, welche Records gelöscht werden

---

## Fazit

**Scavenging ist sinnvoll** für Ihre Umgebung (1670 Records), aber:
- ✅ **Aktivieren** mit längeren Intervallen (28 Tage statt 14)
- ⚠️ **Vorbereitung** ist wichtig (Timestamps setzen)
- 📊 **Monitoring** in den ersten Wochen einrichten
- 🔄 **Reversibel** - kann jederzeit deaktiviert werden

**Risiko:** Mittel (mit richtiger Vorbereitung)
**Nutzen:** Hoch (langfristig bessere Performance)
