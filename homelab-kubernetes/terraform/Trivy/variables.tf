variable "kubeconfig_path" {
  description = "Pfad zur zentralen kubeconfig-Datei"
  type        = string
  default     = "../../vagrant/kubeconfig"
}

variable "trivy_namespace" {
  description = "Namespace für Trivy Operator"
  type        = string
  default     = "trivy-system"
}

variable "trivy_operator_version" {
  description = "Version des Trivy Operator Helm-Charts"
  type        = string
  default     = "0.29.3"
}

variable "trivy_ignore_unfixed" {
  description = "Ignoriere unfixed Vulnerabilities"
  type        = bool
  default     = true
}