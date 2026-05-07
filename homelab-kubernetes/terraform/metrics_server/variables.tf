variable "kubeconfig_path" {
  description = "Pfad zur kubeconfig-Datei für den Zugriff auf das Cluster."
  type        = string
  default     = "../../vagrant/kubeconfig"  # Passe ggf. an deinen tatsächlichen Pfad an
}