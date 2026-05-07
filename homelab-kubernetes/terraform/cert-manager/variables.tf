variable "kubeconfig_path" {
  description = "Pfad zur kubeconfig-Datei für den Zugriff auf das Cluster."
  type        = string
  default     = "../../vagrant/kubeconfig"  # Passe ggf. an deinen tatsächlichen Pfad an
}

variable "letsencrypt_email" {
  description = "E-Mail-Adresse für Let's Encrypt Registrierung (erforderlich für Benachrichtigungen)."
  type        = string
  default     = "acme@example.com"  # Ersetze mit deiner realen E-Mail!
}