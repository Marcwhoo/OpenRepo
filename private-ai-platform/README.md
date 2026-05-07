# private-ai-platform

On-Prem-LLM-Stack als Docker-Compose-Projekt. Wurde intern als Pilot fuer ein eigenes KI-System ohne externe APIs aufgebaut - lokale Modelle, kontrollierte Datenquellen, kein Cloud-Upload.

## Komponenten

- **Ollama** als lokales Modell-Backend (kein Host-Port)
- **Open WebUI** als Chat-Frontend und RAG-Zielsystem
- **Caddy** als HTTPS-Reverse-Proxy
- **SearXNG** (optional) fuer Websuche im internen Docker-Netz
- **Signal-Bridge** (optional, Profil `signal`) fuer 1:1-Chats ueber die Open-WebUI-API

Dazu zwei eigenstaendige RAG-Pipelines:

- **Intranet-RAG** crawlt eine NTLM-geschuetzte Website (Sitemap oder BFS), extrahiert Text aus HTML mit Trafilatura und einem Contao-DOM-Fallback, holt PDFs und faellt bei nicht-extrahierbaren Texten auf OCR (`pdf2image` + `tesseract`) zurueck. Schreibt strukturierte `.txt` mit `### INTRANET_SEITE`-Header. Resume und Dedupe ueber SQLite.
- **Directory-RAG** exportiert AD-/LDAP-Eintraege (Filter: aktive Konten, optional Gruppenmitgliedschaft) als `.txt` pro Person mit `### DIRECTORY_ENTRY`-Block.

Beide Pipelines pushen die Dateien ueber `push_to_openwebui_kb.py` per API in eine Knowledge Base. Inhaltsaenderungen werden ueber SHA-256-State erkannt und ersetzen den vorhandenen KB-Eintrag.

## Struktur

| Ordner | Inhalt |
|--------|--------|
| `docker/` | Compose-Stack, `.env.example`, Caddyfile-Vorlage, Signal-Bridge-Image |
| `provision/` | `bootstrap.sh` (Docker, unattended-upgrades), `install-systemd.sh`, systemd-Units fuer Wartung und RAG-Jobs |
| `scripts/intranet_rag/` | Crawler, OWUI-Push, Fullrebuild |
| `scripts/directory_rag/` | LDAP-Export |

## Schnellstart

```bash
cd docker
cp .env.example .env          # Hostname, Modell, ggf. Signal-Variablen
cp Caddyfile.example Caddyfile
docker compose up -d
docker compose exec ollama ollama pull qwen3:4b
```

Open WebUI ist anschliessend ueber den im Caddyfile eingetragenen Hostname erreichbar. Erstkonto anlegen, Modell freischalten.

Fuer einen vollstaendigen Server-Aufbau (Ubuntu Server LTS, systemd-Timer, RAG-Pipelines): siehe [`provision/README.md`](./provision/README.md).
