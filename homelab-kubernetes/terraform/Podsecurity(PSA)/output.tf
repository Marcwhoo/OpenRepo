output "applied_psa_policies" {
  description = "Map der Namespaces zu den angewendeten PSA-Policies"
  value = {
    for ns in var.namespaces : ns => {
      enforce = var.enforce_policy_map[ns]
      audit   = var.enforce_policy_map[ns]
      warn    = var.enforce_policy_map[ns]
    }
  }
}