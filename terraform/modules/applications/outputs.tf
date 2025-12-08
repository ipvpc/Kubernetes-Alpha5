output "deployed_apps" {
  description = "List of deployed application names"
  value       = keys(var.app_configs)
}

output "app_endpoints" {
  description = "Endpoints for deployed applications"
  value = {
    for app_name, config in var.app_configs : app_name => {
      service_name = config.enable_service ? "${app_name}-service" : null
      ingress_host = config.enable_ingress ? config.ingress_host : null
      port         = config.port
    }
  }
}

