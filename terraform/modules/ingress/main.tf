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
      }
    })
  ]

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

