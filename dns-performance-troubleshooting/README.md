# DNS Performance Troubleshooting

Eine methodische Untersuchung zu langsamen RDS-Anmeldungen in einer produktiven Active-Directory-Umgebung, bei der zunaechst DNS-Latenz als Hauptursache vermutet wurde.

## Problemstellung

RDS-Sitzungen brauchten ursprünglich 3–5 Minuten vom Login-Screen bis zum Desktop. Erste Diagnosen (Resolve-DnsName, nslookup) deuteten auf **langsame interne DNS-Aufloesungen** hin (typischerweise 900–1000 ms). Ziel der Untersuchung: objektive DNS-Messwerte vs. Wahrnehmung der Benutzer trennen, Zeitfresser isolieren.

## Vorgehen

Mehrstufige Messung statt „Tool-Hopping“:

1. **Wireshark-Traces** auf den Domain-Controllern (Remote-Capture), um die tatsaechlichen DNS-Response-Zeiten auf Paketebene zu erfassen.
2. **Latenz-Ebenen-Vergleich** zwischen `.NET GetHostEntry`, `Resolve-DnsName` (lokal und remote), `nslookup` und Performance Countern — um auszuschliessen, dass der Fehler im Messverfahren steckt.
3. **DNS-Server-Seite:** SOA-Records, Zonen-Groesse, Scavenging-Status, AD-Replikation zwischen den DCs, Service-Uptime und Memory-Verhalten.
4. **Client-Seite:** WPAD-Auflösungen, Cache-Verhalten, Forwarder-Latenzen.
5. **Andere Kandidaten:** Scheduled Tasks pro RDS-Server, Roaming Profiles, GPO-Verarbeitung, Third-Party-Software — alles, was beim Anmeldezeitpunkt Last erzeugt.

## Erkenntnisse (Zusammenfassung)

- **Interne DNS-Performance** war auf Paketebene im **niedrigen Millisekundenbereich** (Wireshark-Durchschnitt ≈ 3 ms bei ~100.000 Queries im Trace). Die initial gemessenen 900–1000 ms ueber `Resolve-DnsName` waren offenbar ein **voruebergehender Zustand** — spaetere Messungen lagen bei ~45 ms.
- **Externe Forwarder** waren sehr langsam (mehrere Sekunden pro Query), betrafen aber nur ~6 % des Traffics.
- **WPAD** hatte keinen Record und erzeugte wiederkehrende NXDOMAIN-Queries → Workaround: Record gesetzt.
- **DNS-Scavenging** war deaktiviert — Zone war aufgeblaeht, aber kein akuter Performance-Treiber.
- **DNS war nicht die Hauptursache** fuer die RDS-Anmelde-Latenz. Wahrscheinlicher:
  - **1.300+ Scheduled Tasks pro RDS-Host**, viele „bei Anmeldung“
  - Ein grosser Anteil **Roaming Profiles** ueber SMB
  - **GPO-Verarbeitungszeit** am Logon
  - Third-Party-Applikationen mit Logon-Initialisierung

## Scripts (Auswahl)

- `DNS-Wireshark-Trace-Remote.ps1` / `DNS-Wireshark-Install-Remote.ps1` — Wireshark-Capture auf einem remote DC starten
- `DNS-Wireshark-Analyse-*.ps1` — Parsen der Traces (gesamt, nach Domain, SOA, Detail, Slim)
- `DNS-Latenz-Ebenen-Analyse.ps1` — Vergleich `.NET` vs `Resolve-DnsName` vs `nslookup`
- `DNS-AD-Performance-Analyse.ps1` — DC-Seite: AD-Datenbank, DNS-Service, lokale vs. remote Queries
- `DNS-SOA-Record-Analyse.ps1` / `DNS-SOA-Query-Analyse.ps1` — SOA-Performance und -Konfiguration
- `DNS-Scavenging-Erklaerung.md` — Hintergrund und Empfehlung zu Scavenging-Intervallen
- `DNS-WPAD-Analyse.ps1` / `DNS-WPAD-Record-Setzen.ps1` — WPAD-Diagnose und Fix
- `DNS-Performance-Counter-Aktivieren*.ps1` — Query-Rates via PerfCounter erfassen
- `DNS-Zone-Analyse.ps1`, `DNS-Cache-Analyse.ps1`, `DNS-Server-Cache-Diagnose.ps1`

Die Scripts erwarten Parameter oder Platzhalter fuer Domain-FQDN, DC-Hostnamen und interne IPs; konkrete Werte der Produktivumgebung sind nicht enthalten.

## Take-away

Der Wert dieses Ordners liegt weniger in einer „goldenen Loesung“ als in der Methodik: **messen statt annehmen**, mehrere Messverfahren gegeneinander validieren, und die initiale Hypothese explizit durch Daten widerlegen duerfen.
