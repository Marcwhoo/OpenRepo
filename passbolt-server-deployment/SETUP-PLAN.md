# Passbolt Deployment Plan

## Uebersicht

Passbolt Community Edition fuer 6-köpfiges IT-Team auf Linux-VM mit Docker.

---

## Voraussetzungen (vor Start)

- [ ] VM-Ressourcen: 2 GB RAM, 2 Cores, 30 GB Disk
- [ ] Ubuntu Server 24.04 LTS Image
- [ ] Statische IP fuer VM
- [ ] DNS-A-Record (z.B. passbolt.eure-domain.de)
- [ ] SMTP-Zugangsdaten
- [ ] Admin-E-Mail-Adresse

---

## Steps

### Step 1: VM erstellen und Linux installieren
- VM im Cluster anlegen
- Ubuntu Server 24.04 LTS installieren
- Netzwerk konfigurieren (statische IP)
- SSH-Zugang pruefen

### Step 2: Basis-System vorbereiten
- System updaten (`apt update && apt upgrade`)
- Zeitzone und NTP pruefen
- Firewall (ufw) konfigurieren falls noetig

### Step 3: Docker installieren
- Docker Repository hinzufuegen
- Docker Engine installieren
- Docker Compose installieren
- Benutzer zu docker-Gruppe hinzufuegen

### Step 4: Passbolt Docker-Compose vorbereiten
- docker-compose-ce.yaml herunterladen
- Umgebungsvariablen konfigurieren (URL, DB, SMTP)
- Dateien auf VM kopieren

### Step 5: Passbolt starten
- Container starten
- Logs pruefen
- Erreichbarkeit im Browser testen

### Step 6: SSL/HTTPS einrichten
- Let's Encrypt Zertifikat (Certbot) oder Reverse Proxy
- HTTPS erzwingen

### Step 7: Ersten Admin anlegen
- Setup-Link ausfuehren
- Admin-Account registrieren
- Recovery-Kit sichern

### Step 8: Team einrichten
- Benutzer anlegen
- Gruppen erstellen
- Erste Passwoerter anlegen und freigeben

---

## Notizen

- Domain: _________________
- SMTP Host: _________________
- Admin E-Mail: _________________
