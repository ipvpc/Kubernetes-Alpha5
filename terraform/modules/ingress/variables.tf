variable "environment" {
  description = "Environment name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ingress"
  type        = string
  default     = "traefik"
}

variable "enable_ingress_controller" {
  description = "Enable Traefik Ingress Controller"
  type        = bool
  default     = true
}

variable "ingress_chart_version" {
  description = "Traefik chart version"
  type        = string
  default     = "27.0.0"
}

variable "ingress_replicas" {
  description = "Number of ingress controller replicas"
  type        = number
  default     = 2
  nullable    = true
}

variable "ingress_cpu_request" {
  description = "Ingress controller CPU request"
  type        = string
  default     = "100m"
  nullable    = true
}

variable "ingress_memory_request" {
  description = "Ingress controller memory request"
  type        = string
  default     = "128Mi"
  nullable    = true
}

variable "ingress_cpu_limit" {
  description = "Ingress controller CPU limit"
  type        = string
  default     = "500m"
  nullable    = true
}

variable "ingress_memory_limit" {
  description = "Ingress controller memory limit"
  type        = string
  default     = "512Mi"
  nullable    = true
}

variable "ingress_service_type" {
  description = "Ingress service type (LoadBalancer, NodePort, ClusterIP)"
  type        = string
  default     = "LoadBalancer"
}

variable "ingress_external_ips" {
  description = "External IPs for the ingress service (use node IPs when hostNetwork is true)"
  type        = list(string)
  default     = []
}

