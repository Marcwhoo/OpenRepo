#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="/opt/private-ai-platform/scripts/intranet_rag"
ENV_FILE="${SCRIPT_DIR}/.env"
VENV_PYTHON="${SCRIPT_DIR}/venv/bin/python"
OUTPUT_DIR="${INTRANET_OUTPUT_DIR:-/opt/private-ai-platform/data/intranet-rag}"
STATE_FILE="${OPENWEBUI_KB_STATE_FILE:-${OUTPUT_DIR}/.openwebui-state.json}"
FULLREBUILD_MAX_PAGES="${FULLREBUILD_MAX_PAGES:-5000}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[fullrebuild] $(ts) $*"; }

exec 200>/run/private-ai-platform-intranet-rag-fullrebuild.lock
flock -n 200 || { log "ABBRUCH: Lock bereits gehalten, anderer Lauf aktiv."; exit 1; }

cleanup() {
    log "Trap: Regulaere Timer reaktivieren ..."
    systemctl enable private-ai-platform-intranet-rag-ingest.timer private-ai-platform-intranet-rag-owui-push.timer && \
        systemctl start private-ai-platform-intranet-rag-ingest.timer private-ai-platform-intranet-rag-owui-push.timer || \
        log "WARNUNG: Regulaere Timer konnten nicht reaktiviert werden."
    systemctl disable private-ai-platform-intranet-rag-fullrebuild.timer 2>/dev/null || true
    log "Trap abgeschlossen."
}
trap cleanup EXIT

log "=== Fullrebuild gestartet ==="

log "Regulaere Timer stoppen und deaktivieren ..."
systemctl stop private-ai-platform-intranet-rag-ingest.timer private-ai-platform-intranet-rag-owui-push.timer 2>/dev/null || true
systemctl disable private-ai-platform-intranet-rag-ingest.timer private-ai-platform-intranet-rag-owui-push.timer 2>/dev/null || true

log "Daten und State loeschen ..."
rm -f "${OUTPUT_DIR}"/*.txt "${OUTPUT_DIR}"/.ingest-state.sqlite3
rm -f "${STATE_FILE}" 2>/dev/null || true

log "Env wird ueber systemd EnvironmentFile bereitgestellt."

export INTRANET_MAX_PAGES="${FULLREBUILD_MAX_PAGES}"
log "Ingest starten (MAX_PAGES=${INTRANET_MAX_PAGES}) ..."
"${VENV_PYTHON}" "${SCRIPT_DIR}/ingest.py"
log "Ingest abgeschlossen."

log "Push nach OWUI KB (--prune) ..."
"${VENV_PYTHON}" "${SCRIPT_DIR}/push_to_openwebui_kb.py" --prune
log "Push abgeschlossen."

log "Versuche OWUI Reindex via API ..."
OWUI_BASE="${OPENWEBUI_BASE_URL:-}"
OWUI_KEY="${OPENWEBUI_API_KEY:-}"
if [ -n "${OWUI_BASE}" ] && [ -n "${OWUI_KEY}" ]; then
    REINDEX_HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H "Authorization: Bearer ${OWUI_KEY}" \
        -H "Accept: application/json" \
        --max-time 30 \
        "${OWUI_BASE%/}/api/v1/utils/reindex" 2>/dev/null || echo "000")
    if [ "${REINDEX_HTTP}" = "200" ] || [ "${REINDEX_HTTP}" = "202" ]; then
        log "OWUI Reindex gestartet (HTTP ${REINDEX_HTTP}). Fortschritt in der Admin-Oberflaeche pruefen."
    else
        log "OWUI Reindex-API nicht verfuegbar (HTTP ${REINDEX_HTTP}). Manuell: Admin > Einstellungen > Dokumente > Neu indizieren"
    fi
else
    log "OPENWEBUI_BASE_URL oder OPENWEBUI_API_KEY nicht gesetzt; Reindex manuell: Admin > Einstellungen > Dokumente > Neu indizieren"
fi
log "=== Fullrebuild beendet ==="
