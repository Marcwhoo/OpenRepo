output "cert_manager_status_command" {
  description = "Befehl zum Überprüfen des cert-manager-Status."
  value       = "kubectl get pods -n cert-manager"
}

output "issuer_status_command" {
  description = "Befehl zum Überprüfen der ClusterIssuers."
  value       = "kubectl get clusterissuer"
}

output "ca_issuer_status" {
  description = "Befehl zum Überprüfen des CA Issuers."
  value       = "kubectl describe clusterissuer ca-issuer"
}

output "letsencrypt_status" {
  description = "Befehl zum Überprüfen des Let's Encrypt Issuers."
  value       = "kubectl describe clusterissuer letsencrypt"
}

output "ca_root_cert" {
  description = "CA Root Certificate (für Browser-Import)."
  value       = tls_self_signed_cert.ca_root.cert_pem
  sensitive   = false
}

output "setup_note" {
  description = "Hinweis zur Nutzung."
  value       = "Cert-manager ist installiert mit privater CA und Let's Encrypt. Private CA für interne Services, Let's Encrypt für externe Domains. Importiere das CA Root Certificate in deine Browser für interne Services."
} 