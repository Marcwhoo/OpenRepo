output "pihole_dns_vip" {
  description = "VIP für PiHole-DNS (Port 53)."
  value       = var.pihole_dns_vip
}

output "pihole_web_url" {
  description = "URL für PiHole-WebUI (HTTPS)."
  value       = "https://${var.pihole_web_host}"
}

output "pihole_status_command" {
  description = "Befehl zum Überprüfen von PiHole-Pods."
  value       = "kubectl get pods -n pihole"
}

output "setup_note" {
  description = "Hinweis zur Nutzung."
  value       = "führe noch das pihole settings.sh aus um das pw zu ändern und den richtigen path zu setzen (veraltetes helm chart) "
}