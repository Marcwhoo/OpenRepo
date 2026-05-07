output "metallb_status" {
  value = "kubectl get pods -n metallb-system"
}

output "note" {
  value = "MetalLB ready. Setze Services auf type: LoadBalancer für VIPs."
}