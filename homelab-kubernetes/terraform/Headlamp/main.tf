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

# Namespace erstellen
resource "kubernetes_namespace" "headlamp" {
  metadata {
    name = "headlamp"
  }
}

# Helm Release für Headlamp (HTTP-only mit LoadBalancer)
resource "helm_release" "headlamp" {
  name       = "headlamp"
  repository = "https://kubernetes-sigs.github.io/headlamp/"
  chart      = "headlamp"
  namespace  = kubernetes_namespace.headlamp.metadata[0].name
  version    = "0.32.1"

  set {
    name  = "service.type"
    value = "LoadBalancer"  # VIP für HTTP (Port 80)
  }

  set {
    name  = "ingress.enabled"
    value = "false"  # Kein Helm-Ingress, verwende separaten Terraform-Ingress
  }

  set {
    name  = "rbac.create"
    value = true
  }

  set {
    name  = "rbac.clusterAdminRole"
    value = true
  }

  timeout = 300
}

# Service Account
resource "kubernetes_service_account" "headlamp_admin" {
  depends_on = [helm_release.headlamp]

  metadata {
    name      = "headlamp-admin"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
}

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "headlamp_admin_binding" {
  depends_on = [kubernetes_service_account.headlamp_admin]

  metadata {
    name = "headlamp-admin-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "headlamp-admin"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }

  lifecycle {
    ignore_changes = [metadata[0].name]
  }
}

# Ingress für Headlamp (HTTPS mit cert-manager)
resource "kubernetes_ingress_v1" "headlamp_ingress" {
  depends_on = [helm_release.headlamp]

  metadata {
    name      = "headlamp-ingress"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "ca-issuer"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [var.ingress_host]
      secret_name = var.tls_secret_name
    }
    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "headlamp"
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