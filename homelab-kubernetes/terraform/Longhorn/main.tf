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

resource "kubernetes_namespace" "longhorn" {
  metadata {
    name = var.longhorn_namespace
  }
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  namespace  = var.longhorn_namespace
  create_namespace = false # Namespace wird separat angelegt!
  version    = var.longhorn_chart_version
  timeout    = 12000
  depends_on = [kubernetes_namespace.longhorn]

  set {
    name  = "defaultSettings.defaultReplicaCount"
    value = "2" # Volumes auf beiden Nodes
  }
  set {
    name  = "defaultSettings.replicaAutoBalance"
    value = "least-effort"
  }
  set {
    name  = "defaultSettings.guaranteedEngineManagerCPU"
    value = "10"
  }
  set {
    name  = "defaultSettings.guaranteedReplicaManagerCPU"
    value = "10"
  }
  set {
    name  = "defaultSettings.createDefaultDiskLabeledNodes"
    value = "true"
  }
  set {
    name  = "defaultSettings.allowRecurringJobWhileVolumeDetached"
    value = "false"
  }
  set {
    name  = "defaultSettings.autoSalvage"
    value = "true"
  }
  set {
    name  = "defaultSettings.snapshotDataIntegrity"
    value = "disabled"
  }
  set {
    name  = "defaultSettings.snapshotDataIntegrityImmediateCheckAfterSnapshotCreation"
    value = "false"
  }
  set {
    name  = "defaultSettings.recurringSuccessfulJobsHistoryLimit"
    value = "0"
  }
  set {
    name  = "defaultSettings.recurringFailedJobsHistoryLimit"
    value = "0"
  }
  set {
    name  = "defaultSettings.recurringJobMaxRetention"
    value = "0"
  }
  set {
    name  = "defaultSettings.engineReplicaTimeout"
    value = "8"
  }
  
  # Longhorn Instance Manager Ressourcen
  set {
    name  = "longhornInstanceManager.resources.requests.cpu"
    value = "30m"
  }
  set {
    name  = "longhornInstanceManager.resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "longhornInstanceManager.resources.limits.cpu"
    value = "100m"
  }
  set {
    name  = "longhornInstanceManager.resources.limits.memory"
    value = "128Mi"
  }
  
  # Longhorn Manager Ressourcen
  set {
    name  = "longhornManager.resources.requests.cpu"
    value = "30m"
  }
  set {
    name  = "longhornManager.resources.requests.memory"
    value = "48Mi"
  }
  set {
    name  = "longhornManager.resources.limits.cpu"
    value = "100m"
  }
  set {
    name  = "longhornManager.resources.limits.memory"
    value = "128Mi"
  }
  
  # Longhorn UI Ressourcen
  set {
    name  = "longhornUI.resources.requests.cpu"
    value = "10m"
  }
  set {
    name  = "longhornUI.resources.requests.memory"
    value = "16Mi"
  }
  set {
    name  = "longhornUI.resources.limits.cpu"
    value = "30m"
  }
  set {
    name  = "longhornUI.resources.limits.memory"
    value = "32Mi"
  }
  set {
    name  = "longhornUI.replicas"
    value = "1"
  }
}

resource "kubernetes_service" "longhorn_ui" {
  depends_on = [helm_release.longhorn]
  metadata {
    name      = "longhorn-frontend-lb"
    namespace = var.longhorn_namespace
    annotations = {
      "metallb.universe.tf/allow-shared-ip" = "longhorn-ui"
    }
  }
  spec {
    selector = {
      app = "longhorn-ui"
    }
    type = "LoadBalancer"
    load_balancer_ip = var.longhorn_vip
    port {
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "longhorn_web_ingress" {
  depends_on = [kubernetes_service.longhorn_ui]

  metadata {
    name      = "longhorn-web-ingress"
    namespace = var.longhorn_namespace
    annotations = {
      "cert-manager.io/cluster-issuer" = "ca-issuer"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [var.longhorn_hostname]
      secret_name = "longhorn-tls-secret"
    }
    rule {
      host = var.longhorn_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.longhorn_ui.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
} 