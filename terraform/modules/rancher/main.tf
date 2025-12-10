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
}

# Create ClusterIssuer for Let's Encrypt (if using Let's Encrypt)
resource "kubernetes_manifest" "letsencrypt_issuer" {
  count = var.enable_rancher && var.enable_letsencrypt ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.letsencrypt_issuer_name
    }
    spec = {
      acme = {
        server = var.letsencrypt_server
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-private-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = var.ingress_class
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# Deploy Rancher using Helm
resource "helm_release" "rancher" {
  count = var.enable_rancher ? 1 : 0

  name       = "rancher"
  repository = "https://releases.rancher.com/server-charts/latest"
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
      "kubernetes.io/ingress.class"                = var.ingress_class
      "cert-manager.io/cluster-issuer"             = var.letsencrypt_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    }
  }

  spec {
    ingress_class_name = var.ingress_class

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

