output "grav_namespace" {
  description = "Namespace, in dem Grav läuft"
  value       = var.grav_namespace
}

output "grav_vip" {
  description = "VIP (LoadBalancer IP) für Grav-Service"
  value       = var.grav_vip
}

output "grav_deployment_name" {
  description = "Name des Grav Deployments"
  value       = kubernetes_deployment.grav.metadata[0].name
} 