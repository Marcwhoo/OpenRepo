terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# Helm Release für Metrics Server (neueste Version)
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"  # Offizielle Repo-URL
  chart      = "metrics-server"
  namespace  = "kube-system"  # Standard-Namespace für System-Komponenten; erstelle falls nötig
  version    = "3.12.2"  # Neueste Version (Stand Juli 2025)

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"  # Oft nötig für lokale/Dev-Clusters; entferne für Production
  }

  set {
    name  = "args[1]"
    value = "--kubelet-preferred-address-types=InternalIP"  # Priorisiert interne IPs
  }

  set {
    name  = "rbac.create"
    value = true  # RBAC-Ressourcen erstellen
  }

  timeout = 300
}