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

# Namespace für PiHole
resource "kubernetes_namespace" "pihole" {
  metadata {
    name = "pihole"
  }
}

# Helm Release für PiHole (DNS LoadBalancer, WebUI ClusterIP, Ingress disabled)
resource "helm_release" "pihole" {
  depends_on = [kubernetes_namespace.pihole]

  name       = "pihole"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  namespace  = kubernetes_namespace.pihole.metadata[0].name
  version    = "2.7.0"

  set {
    name  = "serviceDns.type"
    value = "LoadBalancer"
  }

  set {
    name  = "serviceDns.loadBalancerIP"
    value = var.pihole_dns_vip  # Feste VIP
  }

  set {
    name  = "serviceDns.ports.dns"
    value = "53"
  }

  set {
    name  = "serviceDns.ports.dnsUdp"
    value = "53"
  }

  set {
    name  = "serviceDns.annotations.metallb\\.io/allow-shared-ip"
    value = "pihole-dns"
  }

  set {
    name  = "serviceWeb.type"
    value = "LoadBalancer"  # Oder "ClusterIP", je nach Konfig
  }

  set {
    name  = "serviceWeb.loadBalancerIP"
    value = var.pihole_web_vip  # Optional
  }

  set {
    name  = "ingress.enabled"
    value = "false"
  }

  set {
    name  = "persistentVolumeClaim.enabled"
    value = "true"
  }

  set {
    name  = "admin.password"
    value = var.pihole_admin_password  # Set via terraform.tfvars (not committed)
  }

set {
    name  = "livenessProbe.httpGet.path"
    value = "/admin/"  # Neuer Pfad; alternativ "/" für Root
  }

  set {
    name  = "livenessProbe.httpGet.port"
    value = "80"
  }

  set {
    name  = "livenessProbe.failureThreshold"
    value = "5"  # Optional: Anpassen für mehr Toleranz
  }

  # Überschreibe Readiness-Probe ähnlich
  set {
    name  = "readinessProbe.httpGet.path"
    value = "/admin/"
  }

  set {
    name  = "readinessProbe.httpGet.port"
    value = "80"
  }

  set {
    name  = "readinessProbe.failureThreshold"
    value = "3"
  }

  # Blöcke für das öffentliche, aktuelle Image
  set {
    name  = "image.repository"
    value = "pihole/pihole"  # Das offizielle, öffentliche Repo
  }

  set {
    name  = "image.tag"
    value = "latest"  # Oder eine spezifische Version, z. B. "2025.07.1" falls verfügbar
  }

  set {
    name  = "image.pullPolicy"
    value = "Always"  # Zieht das neueste Image
  }

  timeout = 300
}

# Separate Ingress für WebUI (HTTPS, cert-manager)
resource "kubernetes_ingress_v1" "pihole_web_ingress" {
  depends_on = [helm_release.pihole]

  metadata {
    name      = "pihole-web-ingress"
    namespace = kubernetes_namespace.pihole.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "ca-issuer"  # Für TLS
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "nginx.ingress.kubernetes.io/limit-rps" = "10"  # DDoS-Schutz: 10 Requests/Sekunde pro IP
      "nginx.ingress.kubernetes.io/limit-connections" = "5"  # Max 5 Verbindungen pro IP
      "nginx.ingress.kubernetes.io/enable-cors" = "true"  # CORS für WebUI
    }
  }

  spec {
    ingress_class_name = "nginx"
    tls {
      hosts       = [var.pihole_web_host]
      secret_name = "pihole-tls-secret"
    }
    rule {
      host = var.pihole_web_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "pihole-web"
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
