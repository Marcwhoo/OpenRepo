# Marc Hinzmann

Im Hauptjob betreue ich rund 2.000 Endgeraete an 70 Standorten, 80+ VMs auf VMware vSphere HCI sowie den vollstaendigen Windows-Server-Stack (AD, GPO, DNS, DHCP, DFS, RDS, Microsoft 365). Schwerpunkt im Tagesgeschaeft: Automatisierung mit PowerShell und Bash, Endpoint Security, PXE-basierte Geraeteprovisionierung, Migrationen.

Privat baue ich ein eigenes 3-Node-Kubernetes-Cluster (Vagrant, Terraform, MetalLB, Longhorn, NGINX Ingress, cert-manager, Prometheus/Grafana, Pi-hole, Trivy) und arbeite gezielt in Richtung Linux-Administration und DevOps.

Dieses Repository sammelt Skripte, Configs und Dokumentation aus echten Projekten - intern entstanden, fuer die Veroeffentlichung um Hostnamen, Firmennamen, Pfade und vergleichbare interne Werte bereinigt.

## Featured

### [`private-ai-platform`](./private-ai-platform)

On-Prem-LLM-Stack als Docker-Compose-Projekt: Ollama als Modell-Backend, Open WebUI als Chat-Frontend, Caddy als HTTPS-Reverse-Proxy, optional SearXNG fuer interne Websuche und eine Signal-Bridge fuer 1:1-Chats ueber die Open-WebUI-API. Dazu zwei RAG-Pipelines: ein NTLM-faehiger Crawler fuer Intranet-Inhalte (HTML + PDF mit OCR-Fallback) und ein LDAP-Verzeichnisexport. Beide pushen ihre Textdateien per API in Knowledge Bases. Provisionierung via `bootstrap.sh` und systemd-Timer.

### [`homelab-kubernetes`](./homelab-kubernetes)

Mein privater 3-Node-Cluster auf Ubuntu-VMs. Vagrant fuer die VMs, Terraform fuer den kompletten Plattform-Stack: MetalLB, Longhorn, NGINX Ingress, cert-manager, Prometheus/Grafana, Node Exporter, Pi-hole, Trivy. Eine eigene Webapp laeuft mit DynDNS und HTTPS darueber.

### [`passbolt-server-deployment`](./passbolt-server-deployment)

Passbolt CE auf Ubuntu via Docker Compose, intern als unternehmensweiter Passwortmanager im Einsatz. Inklusive AD-Zertifikat-Integration, Postfix-SMTP-Relay, Server-Hardening sowie Backup- und Troubleshooting-Dokumentation.

### [`dns-performance-troubleshooting`](./dns-performance-troubleshooting)

Methodische Analyse zu langsamen RDS-Logons. Wireshark-Captures auf den Domain Controllern, Latenz-Vergleich zwischen `.NET GetHostEntry`, `Resolve-DnsName` und `nslookup`, SOA- und Scavenging-Pruefung, WPAD-Diagnose. Ergebnis: DNS war auf Paketebene im einstelligen Millisekundenbereich; die echten Zeitfresser waren 1.300+ Scheduled Tasks pro RDS-Host, Roaming Profiles und GPO-Verarbeitung.

### [`printer-server-migration`](./printer-server-migration)

Migration von 3 Druckservern (Windows Server 2019 -> 2025) als 6-Phasen-Prozess: Bestandsaufnahme, XML-Export/-Import, Treibermigration, Neuanlage von 170+ GPOs, Sicherheitsgruppen, Benutzerzuordnung, clientseitige Bereinigung. ~80 PowerShell-Skripte plus Ablaufdokumentation.

### [`pxe-iventoy-boot-config`](./pxe-iventoy-boot-config)

iVentoy-PXE mit unattended Windows 11 (Schneegans-Generator, NIC-Treiber-Injection ueber 7z-Archiv, autounattend.xml-Anpassungen fuer iVentoy-spezifische Mount-Reihenfolge) sowie Kickstart, Preseed und cloud-init fuer RHEL, Debian und Ubuntu.

## Weitere Bereiche im Repo

| Bereich | Ordner |
|---------|--------|
| AD und Identity | `active-directory-user-management`, `baramundi-bms-user-export`, `user-profile-cleanup` |
| Endpoint Security | `usb-device-blocking-gpo`, `windows-device-install-restrictions` |
| Provisionierung | `pxe-wds-mdt-deployment`, `windows11-inplace-upgrade`, `office-2016-deployment`, `office-uninstall-sara` |
| VPN und Netzwerk | `openvpn-prelogon-access-provider`, `network-printer-management` |
| Client-Wartung | `windows11-debloat`, `windows-disk-cleanup`, `outlook-autodiscover-registry-fix`, `teams-outlook-addin-repair`, `teamviewer-quicksupport`, `windows-product-key-audit` |

## Tech-Stack

**Linux** Ubuntu Server, Docker, Docker Compose, systemd, Caddy, NGINX, TLS, Bash  
**Container und Orchestrierung** Kubernetes, Helm, Longhorn, MetalLB, NGINX Ingress, cert-manager  
**IaC und Automatisierung** Terraform, Ansible, Vagrant, PowerShell (fortgeschritten), Bash, PXE/MDT  
**Windows Server** Active Directory, GPO, DNS, DHCP, DFS, File Server, RDS, Server 2019/2022/2025  
**Cloud und Identity** Azure (AZ-104 in Vorbereitung), Entra ID, Microsoft 365, Exchange Online  
**Virtualisierung** VMware vSphere, ESXi, HCI  
**Monitoring** Prometheus, Grafana, PRTG, Wireshark  
**Security** Sophos Firewall/VPN, Passbolt, USB Device Control, AD CS  

## Kontakt

Marc Hinzmann, Essen  
GitHub: [@Marcwhoo](https://github.com/Marcwhoo)
