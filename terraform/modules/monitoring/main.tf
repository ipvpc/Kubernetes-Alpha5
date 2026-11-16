# Monitoring Module
# Deploys Prometheus and Grafana for monitoring

locals {
  additional_scrape_configs = [
    for job in var.scrape_jobs : {
      job_name     = job.job_name
      metrics_path = job.metrics_path
      static_configs = [
        {
          targets = job.targets
        }
      ]
    }
  ]

  prometheus_spec = merge(
    {
      resources = {
        requests = {
          cpu    = var.prometheus_cpu_request
          memory = var.prometheus_memory_request
        }
        limits = {
          cpu    = var.prometheus_cpu_limit
          memory = var.prometheus_memory_limit
        }
      }
    },
    length(local.additional_scrape_configs) == 0 ? {} : {
      additionalScrapeConfigs = local.additional_scrape_configs
    }
  )
}

resource "helm_release" "prometheus" {
  count = var.enable_monitoring ? 1 : 0

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_chart_version
  namespace  = var.namespace

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = local.prometheus_spec
      }
      grafana = {
        enabled = var.enable_grafana
        adminPassword = var.grafana_admin_password
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled     = var.enable_grafana_ingress
          hosts       = [var.grafana_ingress_host]
          annotations = {
            "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
  
  # Lifecycle: prevent unnecessary replacement after cluster reboot
  lifecycle {
    ignore_changes = [
      # Ignore changes to status/metadata that might change after reboot
      # Helm will reconcile the release automatically
    ]
  }
}

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

