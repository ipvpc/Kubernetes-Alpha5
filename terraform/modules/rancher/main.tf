# Rancher Deployment Module
# Deploys Rancher management platform with cert-manager for TLS

# Create namespace for Rancher
resource "kubernetes_namespace" "rancher" {
  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
      app         = "rancher"
    }
  }
}

# Create namespace for cert-manager
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.cert_manager_namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
      app         = "cert-manager"
    }
  }
}

# Note: cert-manager CRDs are installed automatically by the Helm chart
# when installCRDs is set to true (which we do in the helm_release below)

# Deploy cert-manager using Helm
resource "helm_release" "cert_manager" {
  count = var.enable_rancher ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = var.cert_manager_namespace
  }

  set {
    name  = "resources.requests.cpu"
    value = var.cert_manager_cpu_request
  }

  set {
    name  = "resources.requests.memory"
    value = var.cert_manager_memory_request
  }

  set {
    name  = "resources.limits.cpu"
    value = var.cert_manager_cpu_limit
  }

  set {
    name  = "resources.limits.memory"
    value = var.cert_manager_memory_limit
  }

  depends_on = [kubernetes_namespace.cert_manager]
  
  # Wait for cert-manager to be fully deployed
  wait = true
  timeout = 600
}

# Wait for cert-manager CRDs to be installed and registered
# CRDs can take time to be fully registered with the API server after Helm installs them
# Increased wait time to ensure CRDs are fully registered before Terraform validates the manifest
resource "time_sleep" "wait_for_cert_manager_crds" {
  count = var.enable_rancher && var.enable_letsencrypt ? 1 : 0

  depends_on = [helm_release.cert_manager]
  
  # Wait 90 seconds for CRDs to be installed and registered with API server
  create_duration = "90s"
}

# Verify cert-manager CRDs are available before creating ClusterIssuer
# This ensures the ClusterIssuer CRD is registered with the API server
resource "null_resource" "verify_cert_manager_crds" {
  count = var.enable_rancher && var.enable_letsencrypt ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Verifying cert-manager CRDs are available..."
      
      max_attempts=40
      attempt=0
      while [ $attempt -lt $max_attempts ]; do
        # kubectl will use KUBECONFIG env var or default ~/.kube/config
        if kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
          # Additional check: verify the CRD is fully registered with API server
          if kubectl api-resources | grep -q "clusterissuers.cert-manager.io"; then
            echo "✓ cert-manager CRDs are available!"
            echo "✓ ClusterIssuer CRD is fully registered with API server"
            exit 0
          else
            echo "CRD exists but not yet registered with API server, waiting..."
          fi
        else
          echo "CRD not found yet, waiting..."
        fi
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts: CRDs not ready yet, waiting 5 seconds..."
        sleep 5
      done
      echo "ERROR: cert-manager CRDs not available after $max_attempts attempts"
      echo "Please check cert-manager installation: kubectl get pods -n ${var.cert_manager_namespace}"
      echo "You can manually check with: kubectl get crd clusterissuers.cert-manager.io"
      exit 1
    EOT
  }

  depends_on = [
    helm_release.cert_manager,
    time_sleep.wait_for_cert_manager_crds
  ]
  
  # Trigger re-run if cert-manager is recreated
  triggers = {
    cert_manager_release = helm_release.cert_manager[0].id
    cert_manager_namespace = var.cert_manager_namespace
  }
}

# Create ClusterIssuer for Let's Encrypt (if using Let's Encrypt)
# Using null_resource with kubectl to avoid Terraform validation issues with CRDs
# This ensures the CRD is available before we try to create the resource
resource "null_resource" "letsencrypt_issuer" {
  count = var.enable_rancher && var.enable_letsencrypt ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Creating Let's Encrypt ClusterIssuer..."
      
      # Create ClusterIssuer YAML
      cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${var.letsencrypt_issuer_name}
spec:
  acme:
    server: ${var.letsencrypt_server}
    email: ${var.letsencrypt_email}
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
    - http01:
        ingress:
          class: ${var.ingress_class}
EOF
      
      echo "✓ ClusterIssuer '${var.letsencrypt_issuer_name}' created successfully"
    EOT
  }

  # Destroy: remove the ClusterIssuer when resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      echo "Removing Let's Encrypt ClusterIssuer..."
      kubectl delete clusterissuer ${self.triggers.letsencrypt_issuer_name} --ignore-not-found=true || true
      echo "✓ ClusterIssuer removed"
    EOT
  }

  depends_on = [
    helm_release.cert_manager,
    time_sleep.wait_for_cert_manager_crds,
    null_resource.verify_cert_manager_crds
  ]
  
  # Trigger re-creation if any of these change
  triggers = {
    cert_manager_release = helm_release.cert_manager[0].id
    letsencrypt_issuer_name = var.letsencrypt_issuer_name
    letsencrypt_server = var.letsencrypt_server
    letsencrypt_email = var.letsencrypt_email
    ingress_class = var.ingress_class
  }
}

# Deploy Rancher using Helm
resource "helm_release" "rancher" {
  count = var.enable_rancher ? 1 : 0

  name       = "rancher"
  repository = "https://releases.rancher.com/server-charts/stable"
  chart      = "rancher"
  version    = var.rancher_chart_version
  namespace  = kubernetes_namespace.rancher.metadata[0].name

  set {
    name  = "hostname"
    value = var.rancher_hostname
  }

  set {
    name  = "bootstrapPassword"
    value = var.rancher_bootstrap_password
  }

  set {
    name  = "ingress.tls.source"
    value = var.rancher_tls_source
  }

  set {
    name  = "ingress.ingressClassName"
    value = var.ingress_class
  }

  set {
    name  = "replicas"
    value = var.rancher_replicas
  }

  set {
    name  = "global.cattle.psp.enabled"
    value = var.enable_psp ? "true" : "false"
  }

  # Resource requests
  set {
    name  = "resources.requests.cpu"
    value = var.rancher_cpu_request
  }

  set {
    name  = "resources.requests.memory"
    value = var.rancher_memory_request
  }

  # Resource limits
  set {
    name  = "resources.limits.cpu"
    value = var.rancher_cpu_limit
  }

  set {
    name  = "resources.limits.memory"
    value = var.rancher_memory_limit
  }

  # Additional settings
  dynamic "set" {
    for_each = var.rancher_additional_settings
    content {
      name  = set.key
      value = set.value
    }
  }

  # Wait for cert-manager to be ready
  # Ingress controller is deployed before this module (via depends_on in main.tf)
  depends_on = [
    helm_release.cert_manager,
    kubernetes_namespace.rancher
  ]

  # Wait for cert-manager to be fully ready before deploying Rancher
  wait = true
  timeout = 600
}

# Create Ingress for Rancher (if not using Rancher's built-in ingress)
resource "kubernetes_ingress_v1" "rancher" {
  count = var.enable_rancher && var.create_external_ingress ? 1 : 0

  metadata {
    name      = "rancher-external-ingress"
    namespace = kubernetes_namespace.rancher.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"             = var.letsencrypt_issuer_name
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
      "traefik.ingress.kubernetes.io/router.tls"  = "true"
    }
  }

    spec {
      ingress_class_name = var.ingress_class
      # Traefik uses IngressRoute CRD, but we'll use standard Ingress for compatibility

    rule {
      host = var.rancher_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "rancher"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [var.rancher_hostname]
      secret_name = "rancher-tls"
    }
  }

  depends_on = [helm_release.rancher]
}

