variable "kubeconfig_path" {
  description = "Pfad zur zentralen kubeconfig-Datei"
  type        = string
  default     = "../../vagrant/kubeconfig"
}

variable "longhorn_namespace" {
  description = "Namespace für Longhorn"
  type        = string
  default     = "longhorn-system"
}

variable "longhorn_chart_version" {
  description = "Longhorn Helm-Chart Version"
  type        = string
  default     = "1.9.1"
}

variable "longhorn_replica_count" {
  description = "Standardanzahl der Replikate pro Volume"
  type        = number
  default     = 1
}

variable "longhorn_vip" {
  description = "VIP für Longhorn Web-UI (MetalLB)"
  type        = string
  default     = "<HOME-NETWORK-IP>"
}

variable "longhorn_hostname" {
  description = "Hostname für Longhorn Web-UI (Ingress)"
  type        = string
  default     = "longhorn.local"
} 