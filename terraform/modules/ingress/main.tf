# Ingress Controller Module
# Deploys Traefik Ingress Controller

resource "helm_release" "traefik" {
  count = var.enable_ingress_controller ? 1 : 0

  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.ingress_chart_version
  namespace  = var.namespace

  values = [
    yamlencode({
      replicas = var.ingress_replicas
      resources = {
        requests = {
          cpu    = var.ingress_cpu_request
          memory = var.ingress_memory_request
        }
        limits = {
          cpu    = var.ingress_cpu_limit
          memory = var.ingress_memory_limit
        }
      }
      service = {
        type = var.ingress_service_type
      }
      # Enable Traefik dashboard
      dashboard = {
        enabled = true
        ingressRoute = true
      }
      # Enable metrics
      metrics = {
        prometheus = {
          enabled = true
        }
      }
      # Global arguments
      globalArguments = []
      # Additional arguments
      additionalArguments = [
        "--log.level=INFO",
        "--accesslog=true",
        "--entrypoints.web.address=:80",
        "--entrypoints.websecure.address=:443",
        "--providers.kubernetesingress=true",
        "--providers.kubernetescrd=true"
      ]
    })
  ]
  
  # Wait for ingress controller to be fully deployed
  wait = true
  timeout = 600
  
  # Allow Helm to skip hooks during uninstall if needed
  skip_crds = false
  
  # Lifecycle: prevent destroy issues by allowing replacement
  lifecycle {
    create_before_destroy = false
    ignore_changes = []
  }

  depends_on = [kubernetes_namespace.ingress]
}

resource "kubernetes_namespace" "ingress" {
  count = var.enable_ingress_controller ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

