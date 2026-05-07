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

# Namespace
resource "kubernetes_namespace" "metallb" {
  metadata {
    name = "metallb-system"
  }
}

# Helm-Release
resource "helm_release" "metallb" {
  depends_on = [kubernetes_namespace.metallb]

  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb.metadata[0].name
  version    = "0.15.0"

  timeout = 300
}

# IP-Pool
resource "kubernetes_manifest" "ip_pool" {
  depends_on = [helm_release.metallb]

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "first-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.ip_pool_range]  # Dein Pool
    }
  }
}

# L2Advertisement
resource "kubernetes_manifest" "l2_advertisement" {
  depends_on = [kubernetes_manifest.ip_pool]

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["first-pool"]
    }
  }
}