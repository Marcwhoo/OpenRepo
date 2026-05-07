#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-0}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

. /etc/os-release || true
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Warning: this script targets Ubuntu."
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg unattended-upgrades apt-transport-https

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/apt/99private-ai-platform-periodic" /etc/apt/apt.conf.d/99private-ai-platform-periodic
cp "${SCRIPT_DIR}/apt/52private-ai-platform-unattended-overrides" /etc/apt/apt.conf.d/52private-ai-platform-unattended-overrides

install -d -m 0755 /opt/private-ai-platform/data/intranet-rag
install -d -m 0755 /opt/private-ai-platform/data/directory-rag

echo "Bootstrap completed."
echo "Next: copy the stack to /opt/private-ai-platform and run install-systemd.sh"
