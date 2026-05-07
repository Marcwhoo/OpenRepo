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

resource "kubernetes_namespace" "trivy" {
  metadata {
    name = var.trivy_namespace
  }
}

resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  namespace  = kubernetes_namespace.trivy.metadata[0].name
  repository = "https://aquasecurity.github.io/helm-charts/"
  chart      = "trivy-operator"
  version    = var.trivy_operator_version

  values = [file("${path.module}/values.yaml")]

  set {
    name  = "trivy.ignoreUnfixed"
    value = var.trivy_ignore_unfixed
  }
  set {
    name  = "serviceMonitor.enabled"
    value = "true"
  }
  set {
    name  = "trivy.securityContext.runAsNonRoot"
    value = "true"
  }
  set {
    name  = "trivy.securityContext.capabilities.drop"
    value = "{ALL}"
  }
  set {
    name  = "trivy.concurrentScanJobsLimit"
    value = "1"
  }

  # CPU und Memory Limits für Trivy
  set {
    name  = "trivy.resources.limits.cpu"
    value = "200m"
  }
  set {
    name  = "trivy.resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "trivy.resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "trivy.resources.requests.memory"
    value = "128Mi"
  }

  # CPU und Memory Limits für den Operator
  set {
    name  = "operator.resources.limits.cpu"
    value = "100m"
  }
  set {
    name  = "operator.resources.limits.memory"
    value = "256Mi"
  }
  set {
    name  = "operator.resources.requests.cpu"
    value = "25m"
  }
  set {
    name  = "operator.resources.requests.memory"
    value = "64Mi"
  }

  # CPU und Memory Limits für Scanner Jobs
  set {
    name  = "scanner.resources.limits.cpu"
    value = "300m"
  }
  set {
    name  = "scanner.resources.limits.memory"
    value = "1Gi"
  }
  set {
    name  = "scanner.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "scanner.resources.requests.memory"
    value = "256Mi"
  }

  # Abhängigkeiten: Warte auf Namespace und Metrics-Server (aus metrics_server/main.tf)
  depends_on = [
    kubernetes_namespace.trivy
  ]
}