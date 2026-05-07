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

# Helm per local-exec auf dem Host installieren (idempotent)
resource "null_resource" "install_helm" {
  provisioner "local-exec" {
    command = <<EOT
      if ! command -v helm >/dev/null 2>&1; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      else
        echo "Helm ist bereits installiert."
      fi
    EOT
  }
} 