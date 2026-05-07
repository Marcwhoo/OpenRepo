variable "kubeconfig_path" {
  description = "Pfad zur kubeconfig-Datei für den Zugriff auf das Cluster."
  type        = string
  default     = "../../vagrant/kubeconfig"  # Passe ggf. an deinen tatsächlichen Pfad an
}

variable "ingress_host" {
  description = "Host für den Ingress (z. B. headlamp.local oder deine IP/Domain)."
  type        = string
  default     = "headlamp.local"  # Passe an deine Domain oder IP an
}

variable "tls_secret_name" {
  description = "Name des TLS-Secrets für HTTPS (erstelle es beforehand)."
  type        = string
  default     = "headlamp-tls-secret"  # Passe an, falls ein anderer Name verwendet wird
}