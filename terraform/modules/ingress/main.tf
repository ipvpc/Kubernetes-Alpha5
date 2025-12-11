# Ingress Controller Module
# Deploys NGINX Ingress Controller

resource "helm_release" "nginx_ingress" {
  count = var.enable_ingress_controller ? 1 : 0

  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_chart_version
  namespace  = var.namespace

  values = [
    yamlencode({
      controller = {
        replicaCount = var.ingress_replicas
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
        # Disable admission webhook to avoid certificate issues during deployment
        # The webhook can cause issues if certificates aren't ready yet
        admissionWebhooks = {
          enabled = false
        }
      }
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

