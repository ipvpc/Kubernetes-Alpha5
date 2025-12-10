environment = "staging"

# kubeconfig_path - leave null to use KUBECONFIG env var or default ~/.kube/config
# kubeconfig_path    = "~/.kube/config"
kubeconfig_path    = null
kubeconfig_context = ""

app_configs = {
  "api-service" = {
    image          = "alpha5/api-service"
    image_tag      = "v1.0.0"
    replicas       = 3
    cpu_request    = "200m"
    memory_request = "256Mi"
    cpu_limit      = "1000m"
    memory_limit   = "1Gi"
    port           = 8080
    env_vars = {
      ENVIRONMENT = "staging"
      LOG_LEVEL   = "info"
      DB_HOST     = "staging-db.example.com"
    }
    enable_ingress = true
    ingress_host   = "api-staging.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
  "web-app" = {
    image          = "alpha5/web-app"
    image_tag      = "v1.0.0"
    replicas       = 3
    cpu_request    = "200m"
    memory_request = "256Mi"
    cpu_limit      = "1000m"
    memory_limit   = "1Gi"
    port           = 3000
    env_vars = {
      ENVIRONMENT = "staging"
      API_URL     = "http://api-service-service:8080"
    }
    enable_ingress = true
    ingress_host   = "app-staging.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
}

common_labels = {
  managed-by = "terraform"
  project    = "alpha5-finance"
  team       = "platform"
}

