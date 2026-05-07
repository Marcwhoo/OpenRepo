variable "kubeconfig_path" {
  type        = string
  default     = "../../vagrant/kubeconfig"
}

variable "ip_pool_range" {
  type        = string
  default     = "<HOME-NETWORK-IP>-<HOME-NETWORK-IP>"
}