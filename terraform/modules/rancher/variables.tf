variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_rancher" {
  description = "Enable Rancher deployment"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Kubernetes namespace for Rancher"
  type        = string
  default     = "cattle-system"
}

variable "cert_manager_namespace" {
  description = "Kubernetes namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "rancher_hostname" {
  description = "Rancher hostname (FQDN)"
  type        = string
}

variable "rancher_bootstrap_password" {
  description = "Rancher bootstrap password (admin user)"
  type        = string
  sensitive   = true
}

variable "rancher_chart_version" {
  description = "Rancher Helm chart version"
  type        = string
  default     = "2.9.0"
}

variable "rancher_replicas" {
  description = "Number of Rancher replicas"
  type        = number
  default     = 3
}

variable "rancher_tls_source" {
  description = "TLS certificate source (rancher, letsEncrypt, secret)"
  type        = string
  default     = "letsEncrypt"
  validation {
    condition     = contains(["rancher", "letsEncrypt", "secret"], var.rancher_tls_source)
    error_message = "TLS source must be one of: rancher, letsEncrypt, secret"
  }
}

variable "ingress_class" {
  description = "Ingress class name"
  type        = string
  default     = "nginx"
}

variable "enable_letsencrypt" {
  description = "Enable Let's Encrypt certificate issuer"
  type        = bool
  default     = true
}

variable "letsencrypt_issuer_name" {
  description = "Let's Encrypt ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

variable "letsencrypt_server" {
  description = "Let's Encrypt server URL"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt registration"
  type        = string
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.13.3"
}

variable "cert_manager_cpu_request" {
  description = "cert-manager CPU request"
  type        = string
  default     = "100m"
}

variable "cert_manager_memory_request" {
  description = "cert-manager memory request"
  type        = string
  default     = "128Mi"
}

variable "cert_manager_cpu_limit" {
  description = "cert-manager CPU limit"
  type        = string
  default     = "500m"
}

variable "cert_manager_memory_limit" {
  description = "cert-manager memory limit"
  type        = string
  default     = "512Mi"
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

variable "enable_psp" {
  description = "Enable Pod Security Policies (deprecated in newer K8s versions)"
  type        = bool
  default     = false
}

variable "create_external_ingress" {
  description = "Create external ingress resource (Rancher has built-in ingress)"
  type        = bool
  default     = false
}

variable "rancher_additional_settings" {
  description = "Additional Rancher Helm chart settings"
  type        = map(string)
  default     = {}
}

