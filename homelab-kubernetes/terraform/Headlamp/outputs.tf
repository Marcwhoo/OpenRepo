output "headlamp_url" {
  description = "URL für Headlamp über Ingress"
  value       = "https://${var.ingress_host}"
}

output "optional_token_command" {
  description = "Token generieren für Headlamp (Login via Kubernetes Token)."
  value       = "kubectl -n headlamp create token headlamp-admin --duration=8760h"  # Erhöht auf 1 Jahr für Bequemlichkeit; passe an
}

output "tls_setup_note" {
  description = "Hinweis zur TLS-Konfiguration"
  value       = "TLS-Secret wird automatisch via Terraform generiert (self-signed für ${var.ingress_host}). Für Production: Verwende cert-manager oder echte Certs."
}