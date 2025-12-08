variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = ""
}

variable "app_configs" {
  description = "Application configurations to deploy"
  type = map(object({
    image           = string
    image_tag       = string
    replicas        = number
    cpu_request     = string
    memory_request  = string
    cpu_limit       = string
    memory_limit    = string
    port            = number
    env_vars        = map(string)
    enable_ingress  = bool
    ingress_host    = string
    enable_service  = bool
    service_type    = string
  }))
  default = {}
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    project    = "alpha5-finance"
  }
}

variable "enable_ingress_controller" {
  description = "Enable NGINX Ingress Controller deployment"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus/Grafana)"
  type        = bool
  default     = false
}

variable "enable_grafana" {
  description = "Enable Grafana (requires enable_monitoring = true)"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "enable_grafana_ingress" {
  description = "Enable Grafana ingress"
  type        = bool
  default     = false
}

variable "grafana_ingress_host" {
  description = "Grafana ingress hostname"
  type        = string
  default     = "grafana.example.com"
}

