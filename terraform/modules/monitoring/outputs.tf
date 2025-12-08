output "prometheus_enabled" {
  description = "Whether Prometheus is enabled"
  value       = var.enable_monitoring
}

output "grafana_enabled" {
  description = "Whether Grafana is enabled"
  value       = var.enable_grafana && var.enable_monitoring
}

