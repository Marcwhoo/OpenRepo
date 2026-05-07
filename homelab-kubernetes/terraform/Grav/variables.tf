variable "kubeconfig_path" {
  description = "Pfad zur zentralen kubeconfig-Datei"
  type        = string
  default     = "../../vagrant/kubeconfig"
}

variable "grav_namespace" {
  description = "Namespace für Grav"
  type        = string
  default     = "grav"
}

variable "grav_image" {
  description = "Grav Docker-Image (z.B. linuxserver/grav)"
  type        = string
  default     = "lscr.io/linuxserver/grav:latest"
}

variable "grav_vip" {
  description = "Feste VIP für Grav-Service (MetalLB)"
  type        = string
  default     = "<HOME-NETWORK-IP>"
}

variable "grav_storage_size" {
  description = "Größe des Persistent Volumes für Grav"
  type        = string
  default     = "3Gi"  # Reduziert für Standard-VM-Festplattengröße (~20-25GB)
} 

variable "grav_host" {
  description = "Domain fuer Grav (z.B. grav.example.com)"
  type        = string
  default     = "grav.example.com"
}

variable "grav_tls_secret" {
  description = "Name des TLS-Secrets für Grav-Ingress"
  type        = string
  default     = "grav-tls"
}

variable "grav_clusterissuer" {
  description = "Name des cert-manager ClusterIssuers für TLS"
  type        = string
  default     = "letsencrypt"
} 