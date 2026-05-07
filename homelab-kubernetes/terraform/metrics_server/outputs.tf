output "metrics_server_status_command" {
  description = "Befehl zum Überprüfen des Metrics Server-Status."
  value       = "kubectl get pods -n kube-system -l k8s-app=metrics-server"
}

output "metrics_api_test_command" {
  description = "Befehl zum Testen der Metrics API (z. B. Pod-Metriken)."
  value       = "kubectl top pods -A"
}

output "integration_note" {
  description = "Hinweis zur Integration mit Headlamp."
  value       = "Sobald der Metrics Server läuft, zeigt Headlamp automatisch CPU/Memory-Metriken in Pod- und Node-Views an. Keine weitere Konfiguration nötig."
}