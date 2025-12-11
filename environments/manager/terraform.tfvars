# Manager Cluster Configuration
# This environment is for deploying Rancher and management tools

environment = "manager"

kubeconfig_path    = "~/.kube/config-manager"
kubeconfig_context = ""

# Enable Rancher for management cluster
enable_rancher = true

# Rancher Configuration
rancher_hostname         = "rancher.alpha5.finance"  # Change to your domain
rancher_bootstrap_password = "p0w3rb4r"        # Change to a secure password
rancher_replicas         = 3                       # HA setup with 3 replicas
rancher_tls_source       = "rancher"               # Options: rancher (self-signed), letsEncrypt, secret
                                                    # Use "rancher" for HTTP access or quick setup
                                                    # Use "letsEncrypt" for production HTTPS
rancher_ingress_class     = "traefik"

# Let's Encrypt Configuration
# Set to false if you want to use HTTP only or self-signed certs (faster setup)
enable_letsencrypt       = false
letsencrypt_email        = "nfernandes@alpha5cloud.com"     # Change to your email
letsencrypt_issuer_name  = "letsencrypt-prod"

# Rancher Resource Configuration
rancher_cpu_request    = "1000m"
rancher_memory_request = "2Gi"
rancher_cpu_limit      = "2000m"
rancher_memory_limit   = "4Gi"

# Enable Ingress Controller (required for Rancher)
enable_ingress_controller = true

# Optional: Enable monitoring for the manager cluster
enable_monitoring = false

# No application deployments in manager cluster (only Rancher)
app_configs = {}

common_labels = {
  managed-by = "terraform"
  project    = "alpha5-finance"
  team       = "platform"
  cluster-type = "manager"
}

