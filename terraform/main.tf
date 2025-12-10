# Remote state configuration (uncomment and configure as needed)
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "kubernetes/${var.environment}/terraform.tfstate"
#     region         = "us-west-2"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }

# Locals for kubeconfig path expansion
locals {
  # Expand ~ to home directory if kubeconfig_path is provided
  # If kubeconfig_path is null or empty, leave as null to use default kubeconfig discovery
  kubeconfig_path_expanded = var.kubeconfig_path != null && var.kubeconfig_path != "" ? (
    substr(var.kubeconfig_path, 0, 1) == "~" ? replace(var.kubeconfig_path, "~", pathexpand("~")) : var.kubeconfig_path
  ) : null
}

# Configure Kubernetes Provider
# Note: If kubeconfig_path is null, the provider will use KUBECONFIG env var or default ~/.kube/config
# If kubeconfig_path is set, Terraform will validate the file exists - ensure it's present!
provider "kubernetes" {
  config_path    = local.kubeconfig_path_expanded
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    config_path    = local.kubeconfig_path_expanded
    config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
  }
}

# Create namespace for the environment
resource "kubernetes_namespace" "environment" {
  metadata {
    name = var.environment
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# Deploy Ingress Controller (optional)
module "ingress" {
  count = var.enable_ingress_controller ? 1 : 0

  source = "./modules/ingress"

  environment = var.environment
}

# Deploy Monitoring Stack (optional)
module "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  source = "./modules/monitoring"

  environment            = var.environment
  enable_grafana         = var.enable_grafana
  grafana_admin_password = var.grafana_admin_password
  enable_grafana_ingress = var.enable_grafana_ingress
  grafana_ingress_host   = var.grafana_ingress_host
}

# Deploy Rancher (optional)
module "rancher" {
  count = var.enable_rancher ? 1 : 0

  source = "./modules/rancher"

  environment              = var.environment
  rancher_hostname         = var.rancher_hostname
  rancher_bootstrap_password = var.rancher_bootstrap_password
  rancher_replicas         = var.rancher_replicas
  rancher_tls_source       = var.rancher_tls_source
  ingress_class            = var.rancher_ingress_class
  enable_letsencrypt       = var.enable_letsencrypt
  letsencrypt_email        = var.letsencrypt_email
  letsencrypt_issuer_name  = var.letsencrypt_issuer_name
  rancher_cpu_request      = var.rancher_cpu_request
  rancher_memory_request   = var.rancher_memory_request
  rancher_cpu_limit        = var.rancher_cpu_limit
  rancher_memory_limit     = var.rancher_memory_limit
  rancher_additional_settings = var.rancher_additional_settings
}

# Deploy applications using modules
module "applications" {
  source = "./modules/applications"

  environment     = var.environment
  namespace       = kubernetes_namespace.environment.metadata[0].name
  app_configs     = var.app_configs
  common_labels   = var.common_labels
}

