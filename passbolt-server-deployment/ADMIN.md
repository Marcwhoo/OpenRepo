# Passbolt Server - Admin-Dokumentation

## Server-Übersicht

| Eigenschaft | Wert |
|-------------|------|
| Hostname | <INTERNAL-SERVER> |
| IP-Adresse | <IP-ADDRESS> |
| Benutzer | passbolt-app |
| Standort | Firmen-Cluster (Veeam-Backup aktiv) |
| OS | Ubuntu (Noble) |

## Zugriff

- **URL:** https://passbolt.<DOMAIN-FQDN>
- **Admin-Panel:** https://passbolt.<DOMAIN-FQDN>/admin
- **SSH:** `ssh passbolt-app@<INTERNAL-SERVER>` (oder per IP)

## Verzeichnisstruktur

```
/home/passbolt-app/passbolt/
├── .env                 # Konfiguration (chmod 600!)
├── docker-compose-ce.yaml
├── certs/
│   ├── cert.pem         # SSL-Zertifikat (AD-CS)
│   └── key.pem          # SSL-Schluessel
├── backups/             # DB-Dumps (Cronjob taeglich 2 Uhr)
└── ADMIN.md             # Diese Datei
```

## Wichtige Befehle

### Status pruefen
```bash
cd ~/passbolt
docker compose -f docker-compose-ce.yaml ps
```

### Logs
```bash
docker compose -f docker-compose-ce.yaml logs -f passbolt
docker compose -f docker-compose-ce.yaml logs --tail 100 passbolt
```

### Update (Pull + Neustart)
```bash
cd ~/passbolt
docker compose -f docker-compose-ce.yaml pull
docker compose -f docker-compose-ce.yaml up -d
```
**Hinweis:** Kein `--remove-orphans` verwenden!

### E-Mail-Queue leeren (bei Problemen)
```bash
cd ~/passbolt
set -a && source .env && set +a
docker compose -f docker-compose-ce.yaml exec -e MYSQL_PWD="$DB_PASSWORD" db mysql -u passbolt passbolt -e "TRUNCATE TABLE email_queue;"
```

### Backup manuell erstellen
```bash
cd ~/passbolt
set -a && source .env && set +a
docker compose -f docker-compose-ce.yaml exec -T -e MYSQL_PWD="$DB_PASSWORD" db mysqldump -u passbolt passbolt | gzip > backups/passbolt_$(date +%Y%m%d).sql.gz
```

## Konfiguration

### E-Mail
- Direkt an Exchange: mail.<COMPANY-DOMAIN>:25
- Absender: passbolt@<COMPANY-DOMAIN>

### SSL-Zertifikat
- AD-CS-Zertifikat (intern)
- Browser-Warnung normal, wenn AD-CA nicht vertraut
- Erneuerung: cert.pem und key.pem ersetzen, dann `docker compose restart passbolt`

### .env
- Enthaelt DB_PASSWORD und weitere Secrets
- Vollstaendiger Inhalt in Passbolt hinterlegt (Notfall-Backup)
- Nach Aenderung: `chmod 600 .env`

## Automatisierung

| Aufgabe | Zeit | Beschreibung |
|---------|------|--------------|
| DB-Backup | Taeglich 2:00 | Cronjob, speichert in ~/passbolt/backups/ |
| Ubuntu Security-Updates | Taeglich | unattended-upgrades |
| Veeam VM-Backup | Nach Firmen-Richtlinie | Gesamter Server |

## Sicherheit

- **UFW:** Aktiv, nur Ports 22, 80, 443
- **.env:** chmod 600
- **backups/:** chmod 700

## Wiederherstellung

1. DB-Dump: `gunzip < backup.sql.gz | mysql -u passbolt -p passbolt`
2. .env: Aus Passbolt kopieren
3. Zertifikate: Aus sicherer Quelle
4. GPG/JWT-Volumes: Mit Veeam-Restore der VM

