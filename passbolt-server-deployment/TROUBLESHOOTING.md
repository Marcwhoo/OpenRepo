# Passbolt Troubleshooting - weisse Seite

## Schritt 1: Vollstaendiger Neuaufbau

```bash
cd ~/passbolt
docker compose -f docker-compose-ce.yaml down
docker compose -f docker-compose-ce.yaml up -d --force-recreate
```

## Schritt 2: Env-Variablen im Container pruefen

```bash
docker compose -f docker-compose-ce.yaml exec passbolt env | grep APP
```

Sollte zeigen: `APP_FULL_BASE_URL=https://passbolt.<DOMAIN-FQDN>`

Wenn `passbolt.local` erscheint -> .env wird nicht geladen!

## Schritt 3: Cache leeren

```bash
docker compose -f docker-compose-ce.yaml exec passbolt su -m -c "/usr/share/php/passbolt/bin/cake cache clear_all" -s /bin/sh www-data
```

## Schritt 4: Mit IP testen (falls Domain Problem)

In .env aendern:
```
APP_URL=https://<IP-ADDRESS>
```

Dann down/up, Cache leeren, und https://<IP-ADDRESS> im Browser oeffnen.

## Schritt 5: Browser-Konsole pruefen (F12)

- Tab "Console" -> JavaScript-Fehler?
- Tab "Network" -> Welche Requests schlagen fehl (rot)?
