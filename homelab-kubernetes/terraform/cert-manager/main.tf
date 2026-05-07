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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

# Namespace für cert-manager
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# Helm Release für cert-manager
resource "helm_release" "cert_manager" {
  depends_on = [kubernetes_namespace.cert_manager]

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = "v1.15.0"

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  set {
    name  = "global.leaderElection.name"
    value = "cert-manager-controller"
  }

  timeout = 600
}

# Private Key für CA Root
resource "tls_private_key" "ca_root" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Self-signed CA Root Certificate
resource "tls_self_signed_cert" "ca_root" {
  private_key_pem = tls_private_key.ca_root.private_key_pem

  subject {
    common_name  = "Cluster Root CA"
    organization = "Cluster Internal CA"
    country      = "DE"
  }

  validity_period_hours = 87600 # 10 Jahre

  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]

  is_ca_certificate = true
}

# Private CA Root Certificate und Key Secret
resource "kubernetes_secret" "ca_root_secret" {
  depends_on = [helm_release.cert_manager]

  metadata {
    name      = "ca-root-secret"
    namespace = "cert-manager"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = base64encode(tls_self_signed_cert.ca_root.cert_pem)
    "tls.key" = base64encode(tls_private_key.ca_root.private_key_pem)
  }
}

# ClusterIssuer für private CA
resource "kubernetes_manifest" "ca_issuer" {
  depends_on = [kubernetes_secret.ca_root_secret, helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "ca-issuer"
    }
    spec = {
      ca = {
        secretName = "ca-root-secret"
      }
    }
  }
}

# ClusterIssuer für Let's Encrypt (Production)
resource "kubernetes_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }
} 