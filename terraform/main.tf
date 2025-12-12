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

# Wait for Rancher webhook to be ready (if Rancher is installed)
# This prevents "connection refused" errors when creating namespaces
# Rancher webhook intercepts namespace creation and must be ready first
resource "null_resource" "wait_for_rancher_webhook" {
  # Only wait if Rancher might be installed (check if webhook exists)
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Checking for Rancher webhook..."
      
      # Check if Rancher webhook validating admission webhook exists
      if kubectl get validatingadmissionwebhook rancher.cattle.io.namespaces.create-non-kubesystem >/dev/null 2>&1 || \
         kubectl get validatingadmissionwebhook 2>/dev/null | grep -q "rancher.cattle.io"; then
        echo "Rancher webhook detected, waiting for it to be ready..."
        
        max_attempts=60
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
          # Check if webhook service exists
          if kubectl get svc rancher-webhook -n cattle-system >/dev/null 2>&1; then
            # Check if webhook pods are running
            RUNNING_PODS=$(kubectl get pods -n cattle-system -l app=rancher-webhook --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$RUNNING_PODS" -gt 0 ]; then
              # Get current webhook service IP
              WEBHOOK_IP=$(kubectl get svc rancher-webhook -n cattle-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
              # Check if endpoints are ready (this verifies the service is actually routing to pods)
              ENDPOINT_READY=$(kubectl get endpoints rancher-webhook -n cattle-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
              if [ -n "$WEBHOOK_IP" ] && [ -n "$ENDPOINT_READY" ]; then
                echo "✓ Rancher webhook service found at $WEBHOOK_IP"
                echo "✓ Rancher webhook endpoint ready at $ENDPOINT_READY"
                echo "✓ Rancher webhook is ready!"
                exit 0
              fi
            fi
          fi
          attempt=$((attempt + 1))
          if [ $((attempt % 6)) -eq 0 ]; then
            echo "Attempt $attempt/$max_attempts: Checking webhook status..."
            kubectl get pods -n cattle-system -l app=rancher-webhook 2>/dev/null || true
            kubectl get svc rancher-webhook -n cattle-system 2>/dev/null || true
          else
            echo "Attempt $attempt/$max_attempts: Rancher webhook not ready yet, waiting 5 seconds..."
          fi
          sleep 5
        done
        echo "WARNING: Rancher webhook not ready after $max_attempts attempts"
        echo "Troubleshooting steps:"
        echo "  1. Check webhook pods: kubectl get pods -n cattle-system -l app=rancher-webhook"
        echo "  2. Check webhook service: kubectl get svc rancher-webhook -n cattle-system"
        echo "  3. Check webhook endpoints: kubectl get endpoints rancher-webhook -n cattle-system"
        echo "  4. If webhook is broken, you may need to restart it:"
        echo "     kubectl delete pod -n cattle-system -l app=rancher-webhook"
        echo "Proceeding anyway - namespace creation may fail if webhook is not ready..."
      else
        echo "No Rancher webhook detected, skipping wait..."
      fi
    EOT
  }
  
  # Trigger this check on every apply to ensure webhook is ready
  triggers = {
    always_run = timestamp()
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
    # Add annotation to help with Rancher webhook if needed
    annotations = {
      # This annotation can help bypass webhook validation in some cases
      # but we'll rely on waiting for webhook to be ready instead
    }
  }
  
  # Wait for Rancher webhook to be ready before creating namespace
  depends_on = [null_resource.wait_for_rancher_webhook]
}

# Deploy Ingress Controller (optional)
module "ingress" {
  count = var.enable_ingress_controller ? 1 : 0

  source = "./modules/ingress"

  environment            = var.environment
  ingress_external_ips   = var.ingress_external_ips
  ingress_replicas       = var.ingress_replicas
  ingress_cpu_request    = var.ingress_cpu_request
  ingress_memory_request = var.ingress_memory_request
  ingress_cpu_limit      = var.ingress_cpu_limit
  ingress_memory_limit   = var.ingress_memory_limit
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
# Note: Depends on ingress controller to avoid webhook certificate issues
module "rancher" {
  count = var.enable_rancher ? 1 : 0

  source = "./modules/rancher"
  
  # Ensure ingress controller is deployed and ready before Rancher
  # This prevents webhook certificate validation errors
  depends_on = [module.ingress]

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

