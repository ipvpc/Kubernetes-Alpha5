# Quick Start Guide

## Prerequisites Check

```bash
# Check Terraform version
terraform version  # Should be >= 1.0

# Check kubectl access
kubectl cluster-info

# Check Helm version
helm version  # Should be >= 3.0
```

## Step-by-Step Deployment

### 1. Configure Your Application

Edit `environments/dev/terraform.tfvars`:

```hcl
environment = "dev"

app_configs = {
  "my-app" = {
    image          = "your-registry/my-app"
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

### 2. Deploy (Choose Your Method)

#### Option A: Using Scripts

**Bash (Linux/Mac):**
```bash
./scripts/deploy.sh dev init
./scripts/deploy.sh dev plan
./scripts/deploy.sh dev apply
```

#### Option B: Using Make

```bash
make init
make plan ENVIRONMENT=dev
make apply ENVIRONMENT=dev
```

#### Option C: Manual Terraform

```bash
cd terraform
terraform init
terraform plan -var-file="../environments/dev/terraform.tfvars"
terraform apply -var-file="../environments/dev/terraform.tfvars"
```

### 3. Verify Deployment

```bash
# Check namespace
kubectl get namespace dev

# Check deployments
kubectl get deployments -n dev

# Check pods
kubectl get pods -n dev

# Check services
kubectl get services -n dev

# Check ingress
kubectl get ingress -n dev
```

### 4. Access Your Application

```bash
# Get service endpoint
kubectl get svc -n dev

# Port forward (if needed)
kubectl port-forward -n dev svc/my-app-service 8080:8080

# Access via ingress (if configured)
curl http://myapp-dev.example.com
```

## Common Commands

### View Resources

```bash
# All resources in namespace
kubectl get all -n dev

# Describe a deployment
kubectl describe deployment my-app -n dev

# View logs
kubectl logs -n dev deployment/my-app
```

### Update Configuration

1. Edit `environments/dev/terraform.tfvars`
2. Run `terraform plan` to see changes
3. Run `terraform apply` to apply changes

### Destroy Resources

```bash
# Using script
./scripts/deploy.sh dev destroy

# Using Make
make destroy ENVIRONMENT=dev

# Manual
cd terraform
terraform destroy -var-file="../environments/dev/terraform.tfvars"
```

## Troubleshooting

### Issue: Provider Authentication Failed

**Solution:**
```bash
# Verify kubeconfig
kubectl config current-context
kubectl config view

# Set context if needed
kubectl config use-context your-context
```

### Issue: Image Pull Errors

**Solution:**
- Verify image exists in registry
- Check image pull secrets if using private registry
- Verify network connectivity

### Issue: Pods Not Starting

**Solution:**
```bash
# Check pod status
kubectl get pods -n dev

# Describe pod for details
kubectl describe pod <pod-name> -n dev

# Check events
kubectl get events -n dev --sort-by='.lastTimestamp'
```

### Issue: Ingress Not Working

**Solution:**
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl describe ingress -n dev

# Verify DNS/hosts file
```

## Next Steps

1. **Enable Monitoring**: Add `enable_monitoring = true` to terraform.tfvars
2. **Enable Ingress Controller**: Add `enable_ingress_controller = true`
3. **Configure Remote State**: Uncomment backend config in `terraform/versions.tf`
4. **Add More Applications**: Extend `app_configs` in terraform.tfvars
5. **Set Up CI/CD**: Integrate deployment scripts into your pipeline

## Environment-Specific Notes

### Development
- Lower resource limits
- Latest image tags
- Debug logging enabled

### Staging
- Medium resource limits
- Tagged image versions
- Production-like configuration

### Production
- Higher resource limits
- Specific version tags
- Production-grade settings
- Monitoring enabled

