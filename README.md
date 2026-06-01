# Marc Hinzmann

In my main job I support around 2,000 endpoints at 70 sites, 80+ VMs on VMware vSphere HCI as well as the complete Windows Server stack (AD, GPO, DNS, DHCP, DFS, RDS, Microsoft 365). Focus in day-to-day work: automation with PowerShell and Bash, endpoint security, PXE-based device provisioning, migrations.

In my spare time I build my own 3-node Kubernetes cluster (Vagrant, Terraform, MetalLB, Longhorn, NGINX Ingress, cert-manager, Prometheus/Grafana, Pi-hole, Trivy) and am deliberately working toward Linux administration and DevOps.

This repository collects scripts, configs, and documentation from real projects - created internally, sanitized for publication by removing hostnames, company names, paths, and comparable internal values.

## Featured

### [`private-ai-platform`](./private-ai-platform)

On-prem LLM stack as a Docker Compose project: Ollama as model backend, Open WebUI as chat frontend, Caddy as HTTPS reverse proxy, optional SearXNG for internal web search and a Signal bridge for 1:1 chats over the Open WebUI API. Plus two RAG pipelines: an NTLM-capable crawler for intranet content (HTML + PDF with OCR fallback) and an LDAP directory export. Both push their text files via API into Knowledge Bases. Provisioning via `bootstrap.sh` and systemd timer.

### [`homelab-kubernetes`](./homelab-kubernetes)

My private 3-node cluster on Ubuntu VMs. Vagrant for the VMs, Terraform for the complete platform stack: MetalLB, Longhorn, NGINX Ingress, cert-manager, Prometheus/Grafana, Node Exporter, Pi-hole, Trivy. A custom web app runs with DynDNS and HTTPS on top.

### [`passbolt-server-deployment`](./passbolt-server-deployment)

Passbolt CE on Ubuntu via Docker Compose, in use internally as company-wide password manager. Including AD certificate integration, Postfix SMTP relay, server hardening as well as backup and troubleshooting documentation.

### [`dns-performance-troubleshooting`](./dns-performance-troubleshooting)

Methodical analysis of slow RDS logons. Wireshark captures on the domain controllers, latency comparison between `.NET GetHostEntry`, `Resolve-DnsName` and `nslookup`, SOA and scavenging check, WPAD diagnosis. Result: DNS was in the single-digit millisecond range at packet level; the real time sinks were 1,300+ scheduled tasks per RDS host, roaming profiles and GPO processing.

### [`printer-server-migration`](./printer-server-migration)

Migration of 3 print servers (Windows Server 2019 -> 2025) as 6-phase process: inventory, XML export/import, driver migration, recreation of 170+ GPOs, security groups, user assignment, client-side cleanup. ~80 PowerShell scripts plus process documentation.

### [`pxe-iventoy-boot-config`](./pxe-iventoy-boot-config)

iVentoy PXE with unattended Windows 11 (Schneegans generator, NIC driver injection over 7z archive, autounattend.xml adjustments for iVentoy-specific mount order) as well as Kickstart, Preseed and cloud-init for RHEL, Debian and Ubuntu.

## Further areas in the repo

| Area | Folder |
|---------|--------|
| AD and Identity | `active-directory-user-management`, `baramundi-bms-user-export`, `user-profile-cleanup` |
| Endpoint Security | `usb-device-blocking-gpo`, `windows-device-install-restrictions` |
| Provisioning | `pxe-wds-mdt-deployment`, `windows11-inplace-upgrade`, `office-2016-deployment`, `office-uninstall-sara` |
| VPN and Network | `openvpn-prelogon-access-provider`, `network-printer-management` |
| Client Maintenance | `windows11-debloat`, `windows-disk-cleanup`, `outlook-autodiscover-registry-fix`, `teams-outlook-addin-repair`, `teamviewer-quicksupport`, `windows-product-key-audit` |

## Tech Stack

**Linux** Ubuntu Server, Docker, Docker Compose, systemd, Caddy, NGINX, TLS, Bash  
**Container and Orchestration** Kubernetes, Helm, Longhorn, MetalLB, NGINX Ingress, cert-manager  
**IaC and Automation** Terraform, Ansible, Vagrant, PowerShell (advanced), Bash, PXE/MDT  
**Windows Server** Active Directory, GPO, DNS, DHCP, DFS, File Server, RDS, Server 2019/2022/2025  
**Cloud and Identity** Azure (AZ-104 in preparation), Entra ID, Microsoft 365, Exchange Online  
**Virtualization** VMware vSphere, ESXi, HCI  
**Monitoring** Prometheus, Grafana, PRTG, Wireshark  
**Security** Sophos Firewall/VPN, Passbolt, USB Device Control, AD CS  

## Contact

Marc Hinzmann
Website: [@Marc](https://hinzmann.dev)
GitHub: [@Marcwhoo](https://github.com/Marcwhoo)
