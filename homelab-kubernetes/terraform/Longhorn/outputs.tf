output "longhorn_vip" {
  description = "VIP für Longhorn WebUI (LoadBalancer-Service)."
  value       = var.longhorn_vip
}

output "longhorn_web_url" {
  description = "URL für Longhorn WebUI (über Ingress, falls aktiviert)."
  value       = "http://${var.longhorn_hostname}"
}

output "longhorn_namespace" {
  description = "Namespace, in dem Longhorn installiert ist."
  value       = var.longhorn_namespace
}

output "longhorn_status_command" {
  description = "Befehl zum Überprüfen der Longhorn-Pods."
  value       = "kubectl get pods -n ${var.longhorn_namespace}"
} 