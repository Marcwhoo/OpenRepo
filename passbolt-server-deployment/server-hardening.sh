#!/bin/bash
# Server-Hardening: .env-Rechte, UFW-Firewall
# Auf dem Server ausfuehren: chmod +x server-hardening.sh && sudo ./server-hardening.sh

set -e

echo "=== .env Rechte ==="
chmod 600 /home/passbolt-app/passbolt/.env
ls -la /home/passbolt-app/passbolt/.env

echo ""
echo "=== UFW Firewall ==="
ufw allow 22/tcp comment SSH
ufw allow 80/tcp comment HTTP
ufw allow 443/tcp comment HTTPS
ufw --force enable
ufw status

echo ""
echo "Fertig."
