variable "kubeconfig_path" {
  description = "Pfad zur Kubernetes-Konfigurationsdatei"
  type        = string
  default     = "~/.kube/config"
}

variable "namespaces" {
  description = "Liste der Namespaces, auf die PSA-Policies angewendet werden sollen"
  type        = list(string)
  default     = ["default", "kube-system"]
}

variable "enforce_policy_map" {
  description = "Map der Namespaces zu den zu verwendenden PSA-Policies (privileged, baseline, restricted)"
  type        = map(string)
  default = {
    "default"   = "baseline"
    "kube-system" = "privileged"
  }
  
  validation {
    condition = alltrue([
      for policy in values(var.enforce_policy_map) : 
      contains(["privileged", "baseline", "restricted"], policy)
    ])
    error_message = "PSA-Policies müssen 'privileged', 'baseline' oder 'restricted' sein."
  }
} 