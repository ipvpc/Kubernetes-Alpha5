variable "environment" {
  description = "Environment name (dev, staging, prod, manager)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod", "manager"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, manager"
  }
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file (leave null/empty to use default kubeconfig discovery via KUBECONFIG env var or ~/.kube/config)"
  type        = string
  default     = null
  nullable    = true
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
  description = "Enable Traefik Ingress Controller deployment"
  type        = bool
  default     = false
}

variable "ingress_external_ips" {
  description = "External IPs for Traefik service (use node IPs when hostNetwork is true to make internal and external IPs the same)"
  type        = list(string)
  default     = []
}

variable "ingress_replicas" {
  description = "Number of Traefik ingress controller replicas (reduce to 1 for lower resource usage)"
  type        = number
  default     = null
}

variable "ingress_cpu_request" {
  description = "Traefik CPU request (reduce for lower resource usage)"
  type        = string
  default     = null
}

variable "ingress_memory_request" {
  description = "Traefik memory request (reduce for lower resource usage)"
  type        = string
  default     = null
}

variable "ingress_cpu_limit" {
  description = "Traefik CPU limit (reduce for lower resource usage)"
  type        = string
  default     = null
}

variable "ingress_memory_limit" {
  description = "Traefik memory limit (reduce for lower resource usage)"
  type        = string
  default     = null
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

# Rancher Variables
variable "enable_rancher" {
  description = "Enable Rancher deployment"
  type        = bool
  default     = false
}

variable "rancher_hostname" {
  description = "Rancher hostname (FQDN) - required if enable_rancher is true"
  type        = string
  default     = "rancher.example.com"
}

variable "rancher_bootstrap_password" {
  description = "Rancher bootstrap password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rancher_replicas" {
  description = "Number of Rancher replicas (recommended: 3 for HA)"
  type        = number
  default     = 3
}

variable "rancher_tls_source" {
  description = "TLS certificate source for Rancher (rancher, letsEncrypt, secret)"
  type        = string
  default     = "letsEncrypt"
  validation {
    condition     = contains(["rancher", "letsEncrypt", "secret"], var.rancher_tls_source)
    error_message = "TLS source must be one of: rancher, letsEncrypt, secret"
  }
}

variable "rancher_ingress_class" {
  description = "Ingress class for Rancher"
  type        = string
  default     = "traefik"
}

variable "enable_letsencrypt" {
  description = "Enable Let's Encrypt for Rancher TLS certificates"
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt registration"
  type        = string
  default     = "admin@example.com"
}

variable "letsencrypt_issuer_name" {
  description = "Let's Encrypt ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

variable "rancher_cpu_request" {
  description = "Rancher CPU request per replica"
  type        = string
  default     = "1000m"
}

variable "rancher_memory_request" {
  description = "Rancher memory request per replica"
  type        = string
  default     = "2Gi"
}

variable "rancher_cpu_limit" {
  description = "Rancher CPU limit per replica"
  type        = string
  default     = "2000m"
}

variable "rancher_memory_limit" {
  description = "Rancher memory limit per replica"
  type        = string
  default     = "4Gi"
}

variable "rancher_additional_settings" {
  description = "Additional Rancher Helm chart settings (key-value pairs)"
  type        = map(string)
  default     = {}
}

