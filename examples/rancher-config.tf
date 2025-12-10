# Example Rancher Configuration
# Copy relevant sections to your environment's terraform.tfvars

# Enable Rancher deployment
enable_rancher = true

# Basic Rancher Configuration
rancher_hostname         = "rancher.example.com"  # Change to your actual domain
rancher_bootstrap_password = "ChangeMe123!"       # Use a strong password!
rancher_replicas         = 3                      # 3 for HA, 1 for dev/testing
rancher_tls_source       = "letsEncrypt"          # Options: rancher, letsEncrypt, secret

# Ingress Configuration
rancher_ingress_class = "nginx"                    # Must match your ingress controller
enable_ingress_controller = true                  # Required for Rancher

# Let's Encrypt Configuration (for automatic TLS)
enable_letsencrypt       = true
letsencrypt_email        = "admin@example.com"    # Your email for Let's Encrypt
letsencrypt_issuer_name  = "letsencrypt-prod"     # ClusterIssuer name

# Resource Configuration
# Adjust based on your cluster capacity
rancher_cpu_request    = "1000m"   # 1 CPU core per replica
rancher_memory_request = "2Gi"    # 2GB RAM per replica
rancher_cpu_limit      = "2000m"  # 2 CPU cores per replica
rancher_memory_limit   = "4Gi"    # 4GB RAM per replica

# Additional Rancher Settings (optional)
rancher_additional_settings = {
  # Example: Enable audit logging
  # "auditLog.level" = "1"
  # "auditLog.maxAge" = "10"
  # "auditLog.maxBackups" = "10"
  # "auditLog.maxSize" = "100"
}

# Alternative: Using Rancher-generated certificates (for testing)
# rancher_tls_source = "rancher"
# enable_letsencrypt = false

# Alternative: Using existing Kubernetes secret
# rancher_tls_source = "secret"
# You'll need to create the TLS secret manually:
# kubectl create secret tls rancher-tls -n cattle-system \
#   --cert=tls.crt --key=tls.key

