# HTTPS mit Wildcard-Zertifikat

## Voraussetzung: Domain

Das Zertifikat *.<COMPANY-DOMAIN> gilt nur fuer **passbolt.<COMPANY-DOMAIN>**.
NICHT fuer passbolt.<DOMAIN-FQDN> (anderer Domain-Name).

DNS: passbolt.<COMPANY-DOMAIN> -> <IP-ADDRESS> (A-Record anlegen falls nicht vorhanden)

---

## Schritt 1: Zertifikat auf VM extrahieren

```bash
cd ~/passbolt/certs
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -clcerts -nokeys -out leaf.pem
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -cacerts -nokeys -out ca.pem
cat leaf.pem ca.pem > cert.pem
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -nocerts -nodes -out key.pem
rm leaf.pem ca.pem
```

---

## Schritt 2: .env anpassen

APP_URL muss passbolt.<COMPANY-DOMAIN> sein (fuer Zertifikat-Match):

```
APP_URL=https://passbolt.<COMPANY-DOMAIN>
```

---

## Schritt 3: Dateien auf VM

- docker-compose-ce.yaml (mit cert-Mounts)
- .env (mit APP_URL=https://passbolt.<COMPANY-DOMAIN>)

---

## Schritt 4: Container neu starten

```bash
cd ~/passbolt
docker compose -f docker-compose-ce.yaml down
docker compose -f docker-compose-ce.yaml up -d
```

---

## Schritt 5: Zugriff

https://passbolt.<COMPANY-DOMAIN>
