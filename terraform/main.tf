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

# Configure Kubernetes Provider
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
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

# Deploy applications using modules
module "applications" {
  source = "./modules/applications"

  environment     = var.environment
  namespace       = kubernetes_namespace.environment.metadata[0].name
  app_configs     = var.app_configs
  common_labels   = var.common_labels
}

