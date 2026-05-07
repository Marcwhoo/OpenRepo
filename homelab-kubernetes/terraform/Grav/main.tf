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

# Namespace für Grav
resource "kubernetes_namespace" "grav" {
  metadata {
    name = var.grav_namespace
  }
}

# Persistent Volume Claim für Grav
resource "kubernetes_persistent_volume_claim" "grav_pvc" {
  depends_on = [kubernetes_namespace.grav]

  metadata {
    name      = "grav-pvc"
    namespace = kubernetes_namespace.grav.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteMany"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = var.grav_storage_size
      }
    }
  }
}

# Kubernetes Deployment für Grav
resource "kubernetes_deployment" "grav" {
  depends_on = [kubernetes_persistent_volume_claim.grav_pvc]

  metadata {
    name      = "grav"
    namespace = kubernetes_namespace.grav.metadata[0].name
    labels = {
      app = "grav"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "grav"
      }
    }

    template {
      metadata {
        labels = {
          app = "grav"
        }
      }

      spec {
        container {
          image = var.grav_image
          name  = "grav"

          port {
            container_port = 80
          }

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Europe/Berlin"
          }

          volume_mount {
            name       = "grav-data"
            mount_path = "/config"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "grav-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grav_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Kubernetes Service für Grav (LoadBalancer)
resource "kubernetes_service" "grav" {
  depends_on = [kubernetes_deployment.grav]

  metadata {
    name      = "grav"
    namespace = kubernetes_namespace.grav.metadata[0].name
    annotations = {
      "metallb.io/allow-shared-ip" = "grav"
    }
  }

  spec {
    selector = {
      app = "grav"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type             = "LoadBalancer"
    load_balancer_ip = var.grav_vip
  }
}

# Ingress für Grav (HTTPS mit cert-manager)
resource "kubernetes_ingress_v1" "grav_ingress" {
  depends_on = [kubernetes_service.grav]

  metadata {
    name      = "grav-ingress"
    namespace = kubernetes_namespace.grav.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = var.grav_clusterissuer
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "nginx.ingress.kubernetes.io/limit-rps" = "10"
      "nginx.ingress.kubernetes.io/limit-connections" = "5"
    }
  }

  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [var.grav_host]
      secret_name = var.grav_tls_secret
    }
    rule {
      host = var.grav_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "grav"
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