output "trivy_namespace" {
  description = "Namespace des Trivy Operators"
  value       = kubernetes_namespace.trivy.metadata[0].name
}

output "trivy_release_name" {
  description = "Name des Trivy Operator Helm-Releases"
  value       = helm_release.trivy_operator.name
}

output "trivy_scan_status" {
  description = "Beispiel-Befehl zum Überprüfen von Scans (via kubectl)"
  value       = "kubectl get vulnerabilityreports -A"
}