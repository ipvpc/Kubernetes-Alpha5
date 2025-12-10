output "namespace" {
  description = "The namespace created for the environment"
  value       = kubernetes_namespace.environment.metadata[0].name
}

output "deployed_applications" {
  description = "List of deployed applications"
  value       = module.applications.deployed_apps
}

output "application_endpoints" {
  description = "Endpoints for deployed applications"
  value       = module.applications.app_endpoints
}

# Rancher Outputs
output "rancher_url" {
  description = "Rancher access URL"
  value       = var.enable_rancher ? module.rancher[0].rancher_url : null
}

output "rancher_hostname" {
  description = "Rancher hostname"
  value       = var.enable_rancher ? module.rancher[0].rancher_hostname : null
}

output "rancher_namespace" {
  description = "Rancher namespace"
  value       = var.enable_rancher ? module.rancher[0].rancher_namespace : null
}

