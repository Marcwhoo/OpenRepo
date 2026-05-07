#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-0}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${SCRIPT_DIR}/systemd"

install -m 0644 "${UNIT_DIR}/private-ai-platform-unattended-upgrade.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-unattended-upgrade.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-docker-stack-upgrade.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-docker-stack-upgrade.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-ingest.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-ingest.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-owui-push.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-owui-push.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-directory-rag-export.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-directory-rag-export.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-directory-rag-owui-push.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-directory-rag-owui-push.timer" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-fullrebuild.service" /etc/systemd/system/
install -m 0644 "${UNIT_DIR}/private-ai-platform-intranet-rag-fullrebuild.timer" /etc/systemd/system/

if [[ ! -f /etc/default/private-ai-platform-docker ]]; then
  install -m 0644 "${UNIT_DIR}/private-ai-platform-docker.default" /etc/default/private-ai-platform-docker
fi

systemctl daemon-reload
systemctl enable private-ai-platform-unattended-upgrade.timer
systemctl enable private-ai-platform-docker-stack-upgrade.timer

echo "Enabled by default:"
echo "  private-ai-platform-unattended-upgrade.timer"
echo "  private-ai-platform-docker-stack-upgrade.timer"
echo
echo "Optional timers:"
echo "  systemctl enable --now private-ai-platform-intranet-rag-ingest.timer"
echo "  systemctl enable --now private-ai-platform-intranet-rag-owui-push.timer"
echo "  systemctl enable --now private-ai-platform-directory-rag-export.timer"
echo "  systemctl enable --now private-ai-platform-directory-rag-owui-push.timer"
echo "  systemctl enable --now private-ai-platform-intranet-rag-fullrebuild.timer"
