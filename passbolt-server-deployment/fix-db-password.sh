#!/bin/bash
# MariaDB-Passwort fuer passbolt-User zuruecksetzen (ohne Datenverlust)
# Auf dem Server: sed -i 's/\r$//' .env fix-db-password.sh  # CRLF entfernen
# Dann: chmod +x fix-db-password.sh && ./fix-db-password.sh

cd "$(dirname "$0")"
sed -i 's/\r$//' .env 2>/dev/null || true
set -a
source .env
set +a

ROOT_PWD=$(docker compose -f docker-compose-ce.yaml exec -T db printenv MYSQL_ROOT_PASSWORD 2>/dev/null | tr -d '\r\n')
docker compose -f docker-compose-ce.yaml exec -T db mysql -u root -p"$ROOT_PWD" -e "ALTER USER 'passbolt'@'%' IDENTIFIED BY '${DB_PASSWORD}'; ALTER USER 'passbolt'@'localhost' IDENTIFIED BY '${DB_PASSWORD}'; FLUSH PRIVILEGES;"
echo "Passwort zurueckgesetzt. Jetzt: docker compose -f docker-compose-ce.yaml exec -e MYSQL_PWD=\"\$DB_PASSWORD\" db mysql -u passbolt passbolt -e \"TRUNCATE TABLE email_queue;\""
