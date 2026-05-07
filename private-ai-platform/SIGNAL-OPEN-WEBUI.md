# Signal-Bridge

Optionaler Service, der den Open-WebUI-Chat ueber Signal erreichbar macht. Eingehende 1:1-Nachrichten werden gegen eine Allowlist gefiltert und per `POST /api/chat/completions` an Open WebUI weitergereicht.

## Komponenten

- `signal-cli-rest-api` (bbernhard/signal-cli-rest-api) - empfaengt und sendet Signal-Nachrichten ueber das verknuepfte Geraet
- `signal-bridge` - eigener Python-Dienst (aiohttp + SQLite). Allowlist, optionales Pairing pro Absender, Rate-Limit, History pro Sender, Stream-Parser fuer Open-WebUI-Antworten mit Tool-Calls

## Start

```bash
cd docker
docker compose --profile signal up -d --build
```

Ohne Profil bleibt der restliche Stack unveraendert.

## Pflichtvariablen in `docker/.env`

| Variable | Zweck |
|----------|-------|
| `SIGNAL_BOT_NUMBER` | E.164 der registrierten Bot-Nummer |
| `SIGNAL_ALLOWLIST` | komma-getrennte E.164-Nummern, die antworten duerfen |
| `OPENWEBUI_API_KEY` | Bearer-Token aus Open WebUI |
| `OPENWEBUI_MODEL` | Modell-ID wie in der Open-WebUI-UI |

Optional: `PAIRING_ENABLED` + `PAIRING_SECRET`, `OPENWEBUI_KNOWLEDGE_ID` (RAG im Request), `RATE_LIMIT_SECONDS`, Empfangs-Modus (`SIGNAL_RECEIVE_MODE=http` Long-Poll oder `ws`).

## Signal-Registrierung

Die Bot-Nummer muss einmalig im `signal-cli-rest-api`-Container verlinkt werden (QR-Code als Linked Device oder eigenstaendige Registrierung). Das Volume `signal_cli_data` enthaelt danach das Schluesselmaterial der Signal-Identitaet und sollte wie ein Secret behandelt werden.

## TLS zu chat.signal.org

Signal nutzt eine eigene Root-CA, die nicht im `ca-certificates`-Standard enthalten ist. In der Compose-Datei wird `/etc/ssl/certs` des Hosts read-only in beide Container gemountet - die CA muss also im Host-Trust-Store liegen:

```bash
echo | openssl s_client -connect chat.signal.org:443 -servername chat.signal.org -showcerts 2>/dev/null \
  | awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c++} c==2{print} c==2 && /END CERTIFICATE/{exit}' \
  | sudo tee /usr/local/share/ca-certificates/signal-messenger-root.crt
sudo update-ca-certificates
```

Anschliessend `docker compose --profile signal up -d --force-recreate`.

## Betrieb

- Logs: `docker compose logs -f signal-bridge`
- Healthcheck im Container: `http://127.0.0.1:8765/health`
- State (Pairing, Dedupe, History): SQLite unter `/data/bridge.sqlite3` (Volume `signal_bridge_data`)
- Updates: `docker compose --profile signal up -d --build`
