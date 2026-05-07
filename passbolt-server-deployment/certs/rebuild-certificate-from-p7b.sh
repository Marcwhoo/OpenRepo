#!/bin/bash
# Zertifikatskette aus p7b extrahieren - fuer vertrauenswuerdige HTTPS-Verbindung
# Auf VM ausfuehren: cd ~/passbolt/certs && bash rebuild-cert.sh

set -e
cd "$(dirname "$0")"

openssl pkcs7 -in certnew.p7b -print_certs -out cert.pem
chmod 644 cert.pem

echo "cert.pem erstellt. Pruefen:"
openssl x509 -in cert.pem -noout -subject -issuer
