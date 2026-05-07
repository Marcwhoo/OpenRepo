variable "kubeconfig_path" {
  description = "Pfad zur kubeconfig-Datei."
  type        = string
  default     = "../../vagrant/kubeconfig"
}

variable "namespace" {
  description = "Namespace für node-exporter."
  type        = string
  default     = "monitoring"
} 