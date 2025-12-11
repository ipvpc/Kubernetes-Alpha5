# Installation Guide

## Prerequisites

Before installing, ensure you have:

1. **Kubernetes cluster** - A running Kubernetes cluster with kubectl configured
2. **kubectl** - Installed and configured to access your cluster
3. **kubeconfig** - Either:
   - Set `KUBECONFIG` environment variable, OR
   - Have kubeconfig at `~/.kube/config-manager` (for manager environment)

## Quick Installation

### Option 1: Using the Deploy Script (Recommended)

```bash
# 1. Plan the deployment
./scripts/deploy.sh manager plan

# 2. Review the plan, then apply
./scripts/deploy.sh manager apply
```

### Option 2: Manual Terraform Commands

```bash
# 1. Navigate to terraform directory
cd terraform

# 2. Initialize Terraform (first time only)
terraform init

# 3. Plan the deployment
terraform plan -var-file="../environments/manager/terraform.tfvars" -out="tfplan-manager"

# 4. Apply the deployment
terraform apply "tfplan-manager"
```

## Step-by-Step Installation

### Step 1: Clean Up Any Stuck Resources (If Needed)

If you have stuck Helm releases from previous attempts:

```bash
# Check for stuck releases
helm list -A

# If nginx-ingress is stuck, clean it up:
helm uninstall nginx-ingress -n ingress-nginx --no-hooks --timeout 2m || true
kubectl delete namespace ingress-nginx --force --grace-period=0 || true

# Remove from Terraform state if needed
cd terraform
terraform state rm 'module.ingress[0].helm_release.nginx_ingress[0]' || true
```

### Step 2: Verify Prerequisites

```bash
# Check kubectl access
kubectl cluster-info
kubectl get nodes

# Check if kubeconfig is set correctly
echo $KUBECONFIG
# OR
ls -la ~/.kube/config-manager
```

### Step 3: Initialize Terraform (First Time Only)

```bash
cd terraform
terraform init
```

### Step 4: Plan the Deployment

```bash
# Using script
./scripts/deploy.sh manager plan

# OR manually
terraform plan -var-file="../environments/manager/terraform.tfvars" -out="tfplan-manager"
```

### Step 5: Apply the Deployment

```bash
# Using script
./scripts/deploy.sh manager apply

# OR manually
terraform apply "tfplan-manager"
```

**Expected Duration:** 5-10 minutes
- Cert-manager installation: ~2 minutes
- CRD registration wait: ~90 seconds
- Rancher deployment: ~3-5 minutes

## What Gets Installed

1. **NGINX Ingress Controller** - Routes traffic to services
2. **cert-manager** - Manages TLS certificates
3. **Let's Encrypt ClusterIssuer** - Issues SSL certificates automatically
4. **Rancher** - Kubernetes management platform

## Verification

After installation completes, verify everything is running:

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check cert-manager
kubectl get pods -n cert-manager
kubectl get clusterissuer

# Check Rancher
kubectl get pods -n cattle-system

# Get Rancher URL
kubectl get ingress -n cattle-system
```

## Access Rancher

1. Get the Rancher hostname from your `terraform.tfvars` (e.g., `rancher.alpha5.finance`)
2. Ensure DNS points to your ingress controller's external IP
3. Access: `https://rancher.alpha5.finance`
4. Login with:
   - Username: `admin`
   - Password: The bootstrap password from your `terraform.tfvars`

## Troubleshooting

### Issue: Helm release stuck during destroy

```bash
# Force cleanup
helm uninstall nginx-ingress -n ingress-nginx --no-hooks --timeout 2m
kubectl delete namespace ingress-nginx --force --grace-period=0
```

### Issue: CRDs not available

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check CRDs manually
kubectl get crd clusterissuers.cert-manager.io
```

### Issue: Ingress webhook errors

The admission webhook is disabled in the configuration. If you still see errors, ensure the ingress controller is deployed before Rancher.

### Issue: Terraform state issues

```bash
# Refresh state
terraform refresh -var-file="../environments/manager/terraform.tfvars"

# Remove stuck resource from state
terraform state rm 'resource.address'
```

## Next Steps

After successful installation:

1. **Access Rancher UI** - Log in and change the default password
2. **Import Clusters** - Add existing Kubernetes clusters to Rancher
3. **Create New Clusters** - Provision new clusters through Rancher
4. **Configure Monitoring** - Enable monitoring stack if needed
5. **Deploy Applications** - Use the applications module to deploy apps

## Uninstallation

To remove everything:

```bash
./scripts/deploy.sh manager destroy
```

Or manually:

```bash
cd terraform
terraform destroy -var-file="../environments/manager/terraform.tfvars"
```

**Warning:** This will delete all Rancher data and managed cluster configurations.

