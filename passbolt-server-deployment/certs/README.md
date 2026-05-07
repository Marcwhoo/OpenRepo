# SSL Zertifikate

Wildcard *.<COMPANY-DOMAIN> - cert.pem und key.pem hier ablegen.

WICHTIG: Zertifikat gilt fuer passbolt.<COMPANY-DOMAIN>, NICHT passbolt.<DOMAIN-FQDN>!

## Von PFX extrahieren (auf VM):

```bash
cd ~/passbolt/certs
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -clcerts -nokeys -out leaf.pem
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -cacerts -nokeys -out ca.pem
cat leaf.pem ca.pem > cert.pem
openssl pkcs12 -in cert2026-2027-<COMPANY-DOMAIN>.pfx -nocerts -nodes -out key.pem
rm leaf.pem ca.pem
```
