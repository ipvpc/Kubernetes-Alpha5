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
rancher_replicas         = 1                       # Reduced from 3 to 1 for lower resource usage (use 3 for HA)
rancher_tls_source       = "rancher"               # Options: rancher (self-signed), letsEncrypt, secret
                                                    # Use "rancher" for HTTP access or quick setup
                                                    # Use "letsEncrypt" for production HTTPS
rancher_ingress_class     = "traefik"

# Let's Encrypt Configuration
# Set to false if you want to use HTTP only or self-signed certs (faster setup)
enable_letsencrypt       = false
letsencrypt_email        = "nfernandes@alpha5cloud.com"     # Change to your email
letsencrypt_issuer_name  = "letsencrypt-prod"

# Rancher Resource Configuration (Optimized for lower resource usage)
# Reduced from defaults: 1000m/2Gi -> 500m/1Gi (requests), 2000m/4Gi -> 1000m/2Gi (limits)
rancher_cpu_request    = "500m"      # Reduced from 1000m
rancher_memory_request = "1Gi"        # Reduced from 2Gi
rancher_cpu_limit      = "1000m"     # Reduced from 2000m
rancher_memory_limit   = "2Gi"       # Reduced from 4Gi

# Enable Ingress Controller (required for Rancher)
enable_ingress_controller = true

# Traefik Ingress Resource Optimization (reduced for lower resource usage)
ingress_replicas       = 1        # Reduced from 2 to 1 (use 2+ for HA)
ingress_cpu_request    = "50m"    # Reduced from 100m
ingress_memory_request = "64Mi"   # Reduced from 128Mi
ingress_cpu_limit      = "200m"   # Reduced from 500m
ingress_memory_limit   = "256Mi"  # Reduced from 512Mi

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

# Traefik External IPs (use node IPs to make internal and external IPs the same)
ingress_external_ips = [
  "192.168.10.70",  # Replace with your actual node IPs
  "192.168.10.71",
  "192.168.10.72"
]