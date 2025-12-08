# Application Deployment Module
# This module deploys multiple applications to Kubernetes

locals {
  default_labels = merge(
    var.common_labels,
    {
      environment = var.environment
    }
  )
}

# Deploy each application
resource "kubernetes_deployment" "apps" {
  for_each = var.app_configs

  metadata {
    name      = each.key
    namespace = var.namespace
    labels    = merge(local.default_labels, { app = each.key })
  }

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app = each.key
      }
    }

    template {
      metadata {
        labels = merge(local.default_labels, { app = each.key })
      }

      spec {
        container {
          name  = each.key
          image = "${each.value.image}:${each.value.image_tag}"

          port {
            container_port = each.value.port
            name           = "http"
          }

          resources {
            requests = {
              cpu    = each.value.cpu_request
              memory = each.value.memory_request
            }
            limits = {
              cpu    = each.value.cpu_limit
              memory = each.value.memory_limit
            }
          }

          dynamic "env" {
            for_each = each.value.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = each.value.port
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = each.value.port
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Create services for applications
resource "kubernetes_service" "apps" {
  for_each = { for k, v in var.app_configs : k => v if v.enable_service }

  metadata {
    name      = "${each.key}-service"
    namespace = var.namespace
    labels    = merge(local.default_labels, { app = each.key })
  }

  spec {
    type = each.value.service_type

    selector = {
      app = each.key
    }

    port {
      port        = each.value.port
      target_port = each.value.port
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# Create ingress for applications
resource "kubernetes_ingress_v1" "apps" {
  for_each = { for k, v in var.app_configs : k => v if v.enable_ingress }

  metadata {
    name      = "${each.key}-ingress"
    namespace = var.namespace
    labels    = merge(local.default_labels, { app = each.key })
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "cert-manager.io/cluster-issuer"             = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = each.value.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "${each.key}-service"
              port {
                number = each.value.port
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [each.value.ingress_host]
      secret_name = "${each.key}-tls"
    }
  }
}

