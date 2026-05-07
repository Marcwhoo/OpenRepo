variable "kubeconfig_path" {
  description = "Pfad zur kubeconfig-Datei."
  type        = string
  default     = "../../vagrant/kubeconfig"  # Passe an
}

variable "pihole_dns_vip" {
  description = "Feste VIP fÃ¼r PiHole-DNS (Port 53, fÃ¼r Router)."
  type        = string
  default     = "<HOME-NETWORK-IP>"  # Passe an deinen Pool an
}

variable "pihole_web_host" {
  description = "Host fÃ¼r PiHole-WebUI (z. B. pihole.local)."
  type        = string
  default     = "pihole.local"  # Passe an
}

variable "pihole_web_vip" {
  description = "Feste VIP fÃ¼r PiHole-WebUI (optional, fÃ¼r LoadBalancer-Service)"
  type        = string
  default     = "<HOME-NETWORK-IP>"
}