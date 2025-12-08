variable "environment" {
  description = "Environment name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "app_configs" {
  description = "Application configurations"
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
}

variable "common_labels" {
  description = "Common labels"
  type        = map(string)
}

