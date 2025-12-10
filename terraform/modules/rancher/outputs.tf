output "rancher_enabled" {
  description = "Whether Rancher is enabled"
  value       = var.enable_rancher
}

output "rancher_hostname" {
  description = "Rancher hostname"
  value       = var.rancher_hostname
}

output "rancher_namespace" {
  description = "Rancher namespace"
  value       = var.namespace
}

output "cert_manager_namespace" {
  description = "cert-manager namespace"
  value       = var.cert_manager_namespace
}

output "rancher_url" {
  description = "Rancher access URL"
  value       = var.enable_rancher ? "https://${var.rancher_hostname}" : null
}

output "cert_manager_enabled" {
  description = "Whether cert-manager is enabled"
  value       = var.enable_rancher
}

