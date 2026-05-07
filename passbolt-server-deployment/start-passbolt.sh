#!/bin/bash
# Einmaliges Setup + Start. Fuehre aus: cd ~/passbolt && bash deploy.sh
set -e
cd "$(dirname "$0")"

[ -f .env ] || { echo "Fehler: .env fehlt. Kopiere .env.example zu .env und fuelle aus."; exit 1; }
[ -f certs/cert.pem ] || { echo "Zertifikat fehlt. Fuehre aus: cd certs && bash rebuild-cert.sh"; exit 1; }
chmod 644 certs/cert.pem certs/key.pem 2>/dev/null || true

docker compose -f docker-compose-ce.yaml up -d
echo "Passbolt gestartet. Pruefe: https://passbolt.<DOMAIN-FQDN>"
