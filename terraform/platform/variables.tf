variable "kubeconfig_path" {
  description = "Path to kubeconfig. The bootstrap script writes this on the node."
  type        = string
  default     = "~/.kube/config"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Pass with -var or TF_VAR_grafana_admin_password; never commit a real value."
  type        = string
  sensitive   = true
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.14.5"
}

variable "ingress_nginx_version" {
  description = "ingress-nginx chart version."
  type        = string
  default     = "4.10.1"
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "58.2.2"
}
