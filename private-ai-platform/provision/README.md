# Provisionierung

Stellt einen Ubuntu-Server fuer den LLM-Stack bereit.

## bootstrap.sh

Installiert Docker CE, das Compose-Plugin sowie `unattended-upgrades` und legt die Daten-Verzeichnisse unter `/opt/private-ai-platform/data/` an. Als root ausfuehren:

```bash
sudo bash bootstrap.sh
```

## install-systemd.sh

Kopiert die Unit-Dateien aus `systemd/` nach `/etc/systemd/system/` und aktiviert die beiden Standard-Timer:

- `private-ai-platform-unattended-upgrade.timer` - taegliches `unattended-upgrade` (07:00)
- `private-ai-platform-docker-stack-upgrade.timer` - taegliches `docker compose pull` und `up -d`

Automatische Reboots nach Paketupdates sind absichtlich aus (`52*-unattended-overrides`). Neustarts werden geplant.

## Optionale RAG-Timer

Werden nicht automatisch aktiviert. Bei Bedarf einzeln einschalten:

| Unit | Zweck |
|------|-------|
| `private-ai-platform-intranet-rag-ingest.timer` | Crawl der Intranet-Quellen |
| `private-ai-platform-intranet-rag-owui-push.timer` | Push der `.txt` in die Open-WebUI-KB |
| `private-ai-platform-intranet-rag-fullrebuild.timer` | Einmaliger Wipe + Komplettlauf |
| `private-ai-platform-directory-rag-export.timer` | LDAP-/AD-Export |
| `private-ai-platform-directory-rag-owui-push.timer` | Push der Verzeichnisdateien in eine zweite KB |

```bash
systemctl enable --now private-ai-platform-intranet-rag-ingest.timer
systemctl enable --now private-ai-platform-intranet-rag-owui-push.timer
```

## Pfade

- Stack: `/opt/private-ai-platform/docker`
- RAG-Skripte: `/opt/private-ai-platform/scripts/{intranet_rag,directory_rag}`
- Exporte: `/opt/private-ai-platform/data`
- Gemeinsame `.env` der RAG-Jobs: `/opt/private-ai-platform/scripts/intranet_rag/.env` (chmod 600)
