#!/bin/bash
# Cache leeren damit E-Mail-Config (env) greift. Nach docker compose up ausfuehren.
cd "$(dirname "$0")"
docker compose -f docker-compose-ce.yaml exec passbolt /usr/share/php/passbolt/bin/cake cache clear_all
docker compose -f docker-compose-ce.yaml restart passbolt
echo "Cache geleert, Passbolt neu gestartet."
