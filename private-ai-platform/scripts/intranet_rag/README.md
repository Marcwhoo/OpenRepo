# Intranet-RAG

Crawler und Push-Skript, um eine NTLM-geschuetzte Website in eine Open-WebUI-Knowledge-Base zu importieren.

## Skripte

- `ingest.py` - crawlt Sitemap (oder BFS via `INTRANET_DISCOVER_LINKS=1`), extrahiert Text mit Trafilatura und einem Contao-DOM-Fallback, holt PDFs und faellt bei nicht-extrahierbaren Texten auf OCR (`pdf2image` + `tesseract`) zurueck. Schreibt eine `.txt` pro Seite mit `### INTRANET_SEITE`-Header (title, source_url, date, breadcrumb, description). Resume und Dedupe ueber SQLite, ETag/Last-Modified werden ausgewertet.
- `push_to_openwebui_kb.py` - laedt die `.txt` per `POST /api/v1/files/` hoch, wartet auf die Verarbeitung und haengt sie an die KB. Inhaltsaenderungen werden ueber SHA-256 erkannt und ersetzen den vorhandenen Eintrag. `--prune` entfernt KB-Eintraege, deren Datei nicht mehr auf der Platte liegt.
- `run-fullrebuild.sh` - Wipe + Crawl mit hoeherem `INTRANET_MAX_PAGES` + Push mit `--prune` + Reindex-API-Probe. Wird vom `*-fullrebuild.service` gestartet und deaktiviert sich danach selbst.
- `job_debug_log.py` - schreibt Warnungen und Fehler nach `debug.txt` im Output-Verzeichnis.

## Aufbau

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp env.example .env           # INTRANET_BASE_URL, NTLM-User, OWUI-API-Key, KB-ID
chmod 600 .env
./venv/bin/python ingest.py
./venv/bin/python push_to_openwebui_kb.py --dry-run
```

## Wichtige Variablen

| Variable | Zweck |
|----------|-------|
| `INTRANET_BASE_URL` | Basis-URL der Quelle |
| `INTRANET_NTLM_USER` / `_PASS` | `DOMAIN\user` und Passwort fuer NTLM |
| `INTRANET_OUTPUT_DIR` | Zielordner der `.txt` |
| `INTRANET_DISCOVER_LINKS` | `1` = BFS-Crawl, `0` = nur Sitemap |
| `INTRANET_CONCURRENCY` | parallele Worker (1-32) |
| `INTRANET_MAX_PAGES` | Obergrenze Seiten pro Lauf |
| `INTRANET_OCR_LANG` | Sprache fuer Tesseract (`deu`, `eng`, ...) |
| `OPENWEBUI_BASE_URL` / `_API_KEY` / `_KNOWLEDGE_ID` | Push-Ziel |

Vollstaendige Liste mit Defaults steht in `env.example`.
