terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

data "kubernetes_namespace_v1" "existing" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value
  }
}

resource "kubernetes_labels" "psa_enforce" {
  for_each = data.kubernetes_namespace_v1.existing

  api_version = "v1"
  kind        = "Namespace"

  metadata {
    name = each.value.metadata[0].name
  }

  labels = {
    "pod-security.kubernetes.io/enforce"         = var.enforce_policy_map[each.value.metadata[0].name]
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/audit"           = var.enforce_policy_map[each.value.metadata[0].name]
    "pod-security.kubernetes.io/audit-version"   = "latest"
    "pod-security.kubernetes.io/warn"            = var.enforce_policy_map[each.value.metadata[0].name]
    "pod-security.kubernetes.io/warn-version"    = "latest"
  }

  # Abhängigkeit von bestehenden Namespaces (z. B. aus pihole/main.tf oder wordpress/main.tf)
  depends_on = [data.kubernetes_namespace_v1.existing]
}