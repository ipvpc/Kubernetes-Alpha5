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

