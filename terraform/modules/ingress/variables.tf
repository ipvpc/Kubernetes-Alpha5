variable "environment" {
  description = "Environment name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ingress"
  type        = string
  default     = "ingress-nginx"
}

variable "enable_ingress_controller" {
  description = "Enable NGINX Ingress Controller"
  type        = bool
  default     = true
}

variable "ingress_chart_version" {
  description = "NGINX Ingress chart version"
  type        = string
  default     = "4.8.3"
}

variable "ingress_replicas" {
  description = "Number of ingress controller replicas"
  type        = number
  default     = 2
}

variable "ingress_cpu_request" {
  description = "Ingress controller CPU request"
  type        = string
  default     = "100m"
}

variable "ingress_memory_request" {
  description = "Ingress controller memory request"
  type        = string
  default     = "128Mi"
}

variable "ingress_cpu_limit" {
  description = "Ingress controller CPU limit"
  type        = string
  default     = "500m"
}

variable "ingress_memory_limit" {
  description = "Ingress controller memory limit"
  type        = string
  default     = "512Mi"
}

variable "ingress_service_type" {
  description = "Ingress service type (LoadBalancer, NodePort, ClusterIP)"
  type        = string
  default     = "LoadBalancer"
}

