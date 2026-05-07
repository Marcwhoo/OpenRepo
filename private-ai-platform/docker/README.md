# Docker-Stack

Compose-Definition fuer den LLM-Stack. Services:

| Service | Rolle | Host-Port |
|---------|-------|-----------|
| `ollama` | lokales Modell-Backend | nur intern |
| `open-webui` | Chat-Frontend, RAG-Zielsystem | nur intern |
| `caddy` | HTTPS-Reverse-Proxy | 80, 443 |
| `searxng` | Websuche fuer Open WebUI | nur intern |
| `signal-cli-rest-api` | Signal-Empfang/-Versand (Profil `signal`) | nur intern |
| `signal-bridge` | Allowlist + Brueckenlogik zu Open WebUI (Profil `signal`) | nur intern |

## Setup

```bash
cp .env.example .env
cp Caddyfile.example Caddyfile
# Zertifikate in certs/ ablegen oder Caddyfile auf eigene TLS-Quelle anpassen
docker compose up -d
docker compose exec ollama ollama pull <modell>
```

Containername bei abweichendem Compose-Projekt: `docker ps`.

## Signal-Profil

```bash
docker compose --profile signal up -d --build
```

Pflichtvariablen in `.env`: `SIGNAL_BOT_NUMBER`, `SIGNAL_ALLOWLIST`, `OPENWEBUI_API_KEY`, `OPENWEBUI_MODEL`. Details in [`../SIGNAL-OPEN-WEBUI.md`](../SIGNAL-OPEN-WEBUI.md).

## SearXNG

Open WebUI braucht JSON-Responses. Nach dem ersten Start in `searxng/settings.yml` ergaenzen:

```yaml
search:
  formats:
    - html
    - json
```

Such-URL in Open WebUI: `http://searxng:8080/search` (kein `?q=`). Mehr in [`searxng/README.md`](searxng/README.md).
