environment = "prod"

# kubeconfig_path - leave null to use KUBECONFIG env var or default ~/.kube/config
# kubeconfig_path    = "~/.kube/config"
kubeconfig_path    = null
kubeconfig_context = ""

app_configs = {
  "api-service" = {
    image          = "alpha5/api-service"
    image_tag      = "v1.0.0"
    replicas       = 5
    cpu_request    = "500m"
    memory_request = "512Mi"
    cpu_limit      = "2000m"
    memory_limit   = "2Gi"
    port           = 8080
    env_vars = {
      ENVIRONMENT = "production"
      LOG_LEVEL   = "warn"
      DB_HOST     = "prod-db.example.com"
    }
    enable_ingress = true
    ingress_host   = "api.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
  "web-app" = {
    image          = "alpha5/web-app"
    image_tag      = "v1.0.0"
    replicas       = 5
    cpu_request    = "500m"
    memory_request = "512Mi"
    cpu_limit      = "2000m"
    memory_limit   = "2Gi"
    port           = 3000
    env_vars = {
      ENVIRONMENT = "production"
      API_URL     = "http://api-service-service:8080"
    }
    enable_ingress = true
    ingress_host   = "app.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
}

common_labels = {
  managed-by = "terraform"
  project    = "alpha5-finance"
  team       = "platform"
}

