output "ingress_controller_url" {
  description = "URL für den Ingress Controller"
  value       = "http://<HOME-NETWORK-IP>:30080"
}

output "ingress_controller_https_url" {
  description = "HTTPS URL für den Ingress Controller"
  value       = "https://<HOME-NETWORK-IP>:30443"
}

output "ingress_controller_status" {
  description = "Status des Ingress Controllers"
  value       = "Installiert und bereit für Ingress-Ressourcen"
} 