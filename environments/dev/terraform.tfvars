environment = "dev"

kubeconfig_path    = "~/.kube/config"
kubeconfig_context = ""

app_configs = {
  "api-service" = {
    image          = "alpha5/api-service"
    image_tag      = "latest"
    replicas       = 2
    cpu_request    = "100m"
    memory_request = "128Mi"
    cpu_limit      = "500m"
    memory_limit   = "512Mi"
    port           = 8080
    env_vars = {
      ENVIRONMENT = "development"
      LOG_LEVEL   = "debug"
      DB_HOST     = "dev-db.example.com"
    }
    enable_ingress = true
    ingress_host   = "api-dev.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
  "web-app" = {
    image          = "alpha5/web-app"
    image_tag      = "latest"
    replicas       = 2
    cpu_request    = "100m"
    memory_request = "128Mi"
    cpu_limit      = "500m"
    memory_limit   = "512Mi"
    port           = 3000
    env_vars = {
      ENVIRONMENT = "development"
      API_URL     = "http://api-service-service:8080"
    }
    enable_ingress = true
    ingress_host   = "app-dev.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
}

common_labels = {
  managed-by = "terraform"
  project    = "alpha5-finance"
  team       = "platform"
}

