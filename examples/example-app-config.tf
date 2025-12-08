# Example Application Configuration
# Copy this to your environment's terraform.tfvars and customize

app_configs = {
  "example-api" = {
    # Container image configuration
    image     = "your-registry/example-api"
    image_tag = "v1.0.0"

    # Scaling configuration
    replicas = 3

    # Resource requests (minimum resources needed)
    cpu_request    = "200m"    # 0.2 CPU cores
    memory_request = "256Mi"   # 256 MiB

    # Resource limits (maximum resources allowed)
    cpu_limit    = "1000m"     # 1 CPU core
    memory_limit = "1Gi"       # 1 GiB

    # Port configuration
    port = 8080

    # Environment variables
    env_vars = {
      ENVIRONMENT = "production"
      LOG_LEVEL   = "info"
      DB_HOST     = "database.example.com"
      DB_PORT     = "5432"
      REDIS_HOST  = "redis.example.com"
    }

    # Ingress configuration
    enable_ingress = true
    ingress_host   = "api.example.com"

    # Service configuration
    enable_service = true
    service_type   = "ClusterIP"  # Options: ClusterIP, NodePort, LoadBalancer
  }

  "example-worker" = {
    image          = "your-registry/example-worker"
    image_tag      = "v1.0.0"
    replicas       = 2
    cpu_request    = "100m"
    memory_request = "128Mi"
    cpu_limit      = "500m"
    memory_limit   = "512Mi"
    port           = 8080
    env_vars = {
      ENVIRONMENT = "production"
      QUEUE_URL   = "amqp://rabbitmq:5672"
    }
    enable_ingress = false  # Workers typically don't need ingress
    ingress_host   = ""
    enable_service = false  # Workers typically don't need services
    service_type   = "ClusterIP"
  }
}

