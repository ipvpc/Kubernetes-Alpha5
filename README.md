# Kubernetes-Alpha5

A comprehensive Terraform-based solution for deploying Kubernetes clusters and applications across multiple environments (dev, staging, prod).

## Features

- 🚀 **Multi-Environment Support**: Separate configurations for dev, staging, and production
- 📦 **Application Deployment**: Deploy multiple applications with configurable resources
- 🐄 **Rancher Management**: Deploy Rancher for Kubernetes cluster management
- 🔒 **Security**: Namespace isolation and resource limits
- 📊 **Monitoring**: Optional Prometheus and Grafana integration
- 🌐 **Ingress**: Optional NGINX Ingress Controller deployment
- 🏷️ **Labeling**: Consistent labeling strategy across all resources
- 🔄 **CI/CD Ready**: Scripts for automated deployments

## Prerequisites

- Terraform >= 1.0
- Kubernetes cluster access (kubeconfig configured)
- kubectl installed and configured
- Helm 3.x (for monitoring and ingress modules)

## Project Structure

```
.
├── terraform/
│   ├── main.tf                 # Main Terraform configuration
│   ├── variables.tf            # Variable definitions
│   ├── outputs.tf             # Output definitions
│   └── modules/
│       ├── applications/       # Application deployment module
│       ├── monitoring/         # Monitoring stack module
│       ├── ingress/            # Ingress controller module
│       └── rancher/            # Rancher management platform module
├── environments/
│   ├── dev/
│   │   └── terraform.tfvars   # Development environment config
│   ├── staging/
│   │   └── terraform.tfvars   # Staging environment config
│   ├── prod/
│   │   └── terraform.tfvars   # Production environment config
│   └── manager/
│       └── terraform.tfvars   # Manager cluster config (Rancher)
└── scripts/
    ├── deploy.sh              # Bash deployment script
    └── deploy.ps1             # PowerShell deployment script
```

## Quick Start

### 1. Configure Your Environment

Edit the environment-specific `terraform.tfvars` file in `environments/[env]/terraform.tfvars`:

```hcl
environment = "dev"

app_configs = {
  "my-app" = {
    image          = "myregistry/my-app"
    image_tag      = "latest"
    replicas       = 2
    cpu_request    = "100m"
    memory_request = "128Mi"
    cpu_limit      = "500m"
    memory_limit   = "512Mi"
    port           = 8080
    env_vars = {
      ENVIRONMENT = "development"
    }
    enable_ingress = true
    ingress_host   = "myapp-dev.example.com"
    enable_service = true
    service_type   = "ClusterIP"
  }
}
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Plan Deployment

```bash
# Using script (recommended)
./scripts/deploy.sh dev plan

# Or manually
cd terraform
terraform plan -var-file="../environments/dev/terraform.tfvars"
```

### 4. Apply Configuration

```bash
# Using script (recommended)
./scripts/deploy.sh dev apply

# Or manually
cd terraform
terraform apply -var-file="../environments/dev/terraform.tfvars"
```

## Usage

### Deploying to Different Environments

```bash
# Development
./scripts/deploy.sh dev apply

# Staging
./scripts/deploy.sh staging apply

# Production
./scripts/deploy.sh prod apply
```

### Using PowerShell (Windows)

```powershell
.\scripts\deploy.ps1 dev plan
.\scripts\deploy.ps1 dev apply
```

### Manual Terraform Commands

```bash
cd terraform

# Initialize
terraform init

# Validate configuration
terraform validate

# Plan
terraform plan -var-file="../environments/dev/terraform.tfvars"

# Apply
terraform apply -var-file="../environments/dev/terraform.tfvars"

# Destroy (use with caution!)
terraform destroy -var-file="../environments/dev/terraform.tfvars"
```

## Configuration

### Application Configuration

Each application in `app_configs` supports the following options:

| Variable | Description | Example |
|----------|-------------|---------|
| `image` | Container image name | `alpha5/api-service` |
| `image_tag` | Container image tag | `v1.0.0` |
| `replicas` | Number of replicas | `3` |
| `cpu_request` | CPU request | `100m` |
| `memory_request` | Memory request | `128Mi` |
| `cpu_limit` | CPU limit | `500m` |
| `memory_limit` | Memory limit | `512Mi` |
| `port` | Container port | `8080` |
| `env_vars` | Environment variables | `{ ENV = "dev" }` |
| `enable_ingress` | Enable ingress | `true` |
| `ingress_host` | Ingress hostname | `api.example.com` |
| `enable_service` | Enable service | `true` |
| `service_type` | Service type | `ClusterIP` |

### Enabling Monitoring

Add to your `terraform.tfvars`:

```hcl
enable_monitoring = true
enable_grafana = true
grafana_admin_password = "your-secure-password"
enable_grafana_ingress = true
grafana_ingress_host = "grafana.example.com"
```

### Enabling Ingress Controller

Add to your `terraform.tfvars`:

```hcl
enable_ingress_controller = true
```

### Deploying Rancher

For a management cluster, deploy Rancher:

```hcl
enable_rancher = true
rancher_hostname = "rancher.yourdomain.com"
rancher_bootstrap_password = "YourSecurePassword123!"
rancher_replicas = 3
enable_letsencrypt = true
letsencrypt_email = "admin@example.com"
enable_ingress_controller = true
```

See [RANCHER_DEPLOYMENT.md](RANCHER_DEPLOYMENT.md) for detailed Rancher deployment instructions.

## Modules

### Applications Module

Deploys Kubernetes deployments, services, and ingresses for applications.

**Features:**
- Automatic health checks (liveness/readiness probes)
- Resource limits and requests
- Configurable environment variables
- Optional ingress with TLS support

### Monitoring Module

Deploys Prometheus and Grafana using Helm charts.

**Features:**
- Prometheus for metrics collection
- Grafana for visualization
- Configurable resource limits
- Optional ingress for Grafana

### Ingress Module

Deploys NGINX Ingress Controller.

**Features:**
- Configurable replicas
- LoadBalancer or NodePort service types
- Resource limits

## Best Practices

1. **Environment Isolation**: Each environment uses a separate namespace
2. **Resource Limits**: Always set CPU and memory limits
3. **Health Checks**: Applications should implement `/health` and `/ready` endpoints
4. **Labeling**: Consistent labeling for resource management
5. **State Management**: Use remote state backend for production
6. **Secrets**: Use Kubernetes secrets or external secret management
7. **Versioning**: Pin image tags in production

## Remote State (Optional)

To use remote state management, uncomment and configure in `terraform/main.tf`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "kubernetes/${var.environment}/terraform.tfstate"
  region         = "us-west-2"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

## Troubleshooting

### Common Issues

1. **Provider Authentication**: Ensure kubeconfig is properly configured
   ```bash
   kubectl config current-context
   ```

2. **Resource Conflicts**: Check for existing resources in the namespace
   ```bash
   kubectl get all -n <environment>
   ```

3. **Image Pull Errors**: Verify image registry access and credentials

4. **Ingress Not Working**: Ensure ingress controller is deployed
   ```bash
   kubectl get pods -n ingress-nginx
   ```

## Security Considerations

- Use Kubernetes secrets for sensitive data
- Implement network policies for pod-to-pod communication
- Enable RBAC for service accounts
- Use TLS for ingress endpoints
- Regularly update container images
- Review and limit resource quotas

## Contributing

1. Create a feature branch
2. Make your changes
3. Test in dev environment
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For issues and questions, please open an issue in the repository.
