# Rancher Deployment Guide

This guide explains how to deploy Rancher into your Kubernetes management cluster using Terraform.

## Overview

Rancher is a complete software stack for teams adopting containers. It addresses the operational and security challenges of managing multiple Kubernetes clusters across any infrastructure, while providing DevOps teams with integrated tools for running containerized workloads.

## Prerequisites

1. **Kubernetes Cluster**: A running Kubernetes cluster (v1.24+ recommended)
   - **New to Kubernetes?** See [KUBERNETES_INSTALLATION.md](./KUBERNETES_INSTALLATION.md) for automated installation on remote hosts
2. **kubectl**: Configured and connected to your cluster
3. **Helm**: Version 3.x installed
4. **Ingress Controller**: NGINX Ingress Controller (will be deployed automatically if enabled)
5. **DNS**: A DNS record pointing to your cluster's ingress IP
6. **Terraform**: Version >= 1.0

## Automated Kubernetes Installation

If you don't have a Kubernetes cluster yet, you can automatically install one on remote hosts using Ansible:

```bash
# Install Kubernetes on remote hosts
./scripts/install-kubernetes.sh manager kubeadm

# Or using k3s (lightweight)
./scripts/install-kubernetes.sh manager k3s
```

This will:
1. Install Kubernetes on all configured remote hosts
2. Set up the cluster (control plane + workers)
3. Download the kubeconfig to `~/.kube/config-manager`
4. Verify the cluster is ready

See [KUBERNETES_INSTALLATION.md](./KUBERNETES_INSTALLATION.md) for detailed instructions.

## Quick Start

### 1. Configure Rancher Settings

Edit `environments/manager/terraform.tfvars`:

```hcl
enable_rancher = true
rancher_hostname = "rancher.yourdomain.com"
rancher_bootstrap_password = "YourSecurePassword123!"
rancher_replicas = 3
enable_letsencrypt = true
letsencrypt_email = "your-email@example.com"
enable_ingress_controller = true
```

### 2. Deploy Rancher

```bash
# Initialize Terraform
cd terraform
terraform init

# Plan deployment
terraform plan -var-file="../environments/manager/terraform.tfvars"

# Apply configuration
terraform apply -var-file="../environments/manager/terraform.tfvars"
```

Or using the deployment script:

```bash
./scripts/deploy.sh manager plan
./scripts/deploy.sh manager apply
```

### 3. Access Rancher

After deployment, access Rancher at:
- URL: `https://rancher.yourdomain.com`
- Username: `admin`
- Password: The password you set in `rancher_bootstrap_password`

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_rancher` | Enable Rancher deployment | `false` | Yes |
| `rancher_hostname` | FQDN for Rancher | `rancher.example.com` | Yes |
| `rancher_bootstrap_password` | Admin password | - | Yes |
| `rancher_replicas` | Number of replicas | `3` | No |
| `rancher_tls_source` | TLS source | `letsEncrypt` | No |

### TLS Configuration

Rancher supports three TLS sources:

1. **letsEncrypt** (Recommended): Automatic TLS certificates from Let's Encrypt
   ```hcl
   rancher_tls_source = "letsEncrypt"
   enable_letsencrypt = true
   letsencrypt_email = "admin@example.com"
   ```

2. **rancher**: Rancher-generated self-signed certificates
   ```hcl
   rancher_tls_source = "rancher"
   enable_letsencrypt = false
   ```

3. **secret**: Use existing Kubernetes secret
   ```hcl
   rancher_tls_source = "secret"
   # You'll need to create the secret manually
   ```

### High Availability Setup

For production, deploy with 3 replicas:

```hcl
rancher_replicas = 3
rancher_cpu_request = "1000m"
rancher_memory_request = "2Gi"
rancher_cpu_limit = "2000m"
rancher_memory_limit = "4Gi"
```

### Resource Requirements

Minimum resources per replica:
- CPU: 1 core (1000m)
- Memory: 2GB (2Gi)

Recommended for production:
- CPU: 2 cores (2000m)
- Memory: 4GB (4Gi)

## Architecture

The Rancher deployment includes:

1. **cert-manager**: Automatically manages TLS certificates
2. **Rancher Server**: The main Rancher application
3. **NGINX Ingress**: Routes traffic to Rancher (if enabled)

### Namespaces Created

- `cattle-system`: Rancher components
- `cert-manager`: cert-manager components

## Deployment Steps

The Terraform module automatically:

1. Creates namespaces for Rancher and cert-manager
2. Deploys cert-manager using Helm
3. Creates Let's Encrypt ClusterIssuer (if enabled)
4. Deploys Rancher using Helm
5. Configures ingress and TLS

## Verification

### Check Deployment Status

```bash
# Check Rancher pods
kubectl get pods -n cattle-system

# Check cert-manager pods
kubectl get pods -n cert-manager

# Check Rancher service
kubectl get svc -n cattle-system

# Check ingress
kubectl get ingress -n cattle-system
```

### Verify cert-manager

```bash
# Check ClusterIssuer
kubectl get clusterissuer

# Check certificates
kubectl get certificates -n cattle-system
```

### Check Rancher Logs

```bash
# View Rancher logs
kubectl logs -n cattle-system -l app=rancher --tail=100
```

## Post-Deployment

### 1. First Login

1. Navigate to `https://rancher.yourdomain.com`
2. Log in with:
   - Username: `admin`
   - Password: Your bootstrap password
3. Change the password on first login

### 2. Import Existing Clusters

After logging in, you can import existing Kubernetes clusters:

1. Go to **Clusters** → **Import Existing**
2. Follow the instructions to add your clusters

### 3. Create New Clusters

Rancher can provision new clusters on various cloud providers or on-premises.

## Troubleshooting

### Issue: Rancher pods not starting

**Check pod status:**
```bash
kubectl describe pod -n cattle-system -l app=rancher
```

**Common causes:**
- Insufficient resources
- Image pull errors
- Configuration issues

### Issue: TLS certificate not issued

**Check cert-manager:**
```bash
kubectl get certificates -n cattle-system
kubectl describe certificate -n cattle-system rancher-serving-cert
```

**Verify DNS:**
```bash
# Ensure DNS points to your ingress IP
nslookup rancher.yourdomain.com
```

### Issue: Cannot access Rancher UI

**Check ingress:**
```bash
kubectl get ingress -n cattle-system
kubectl describe ingress -n cattle-system
```

**Verify ingress controller:**
```bash
kubectl get pods -n ingress-nginx
```

**Check service:**
```bash
kubectl get svc -n cattle-system
```

### Issue: cert-manager not working

**Check cert-manager pods:**
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

**Verify ClusterIssuer:**
```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Security Considerations

1. **Bootstrap Password**: Use a strong, unique password
2. **TLS**: Always use TLS in production (Let's Encrypt recommended)
3. **Network Policies**: Consider implementing network policies
4. **RBAC**: Rancher manages RBAC, but ensure cluster-level RBAC is configured
5. **Updates**: Keep Rancher updated to the latest stable version

## Upgrading Rancher

To upgrade Rancher, update the `rancher_chart_version` in your terraform.tfvars:

```hcl
# In terraform/modules/rancher/variables.tf or override in terraform.tfvars
rancher_chart_version = "2.9.1"  # Update to desired version
```

Then apply:

```bash
terraform apply -var-file="../environments/manager/terraform.tfvars"
```

## Backup and Recovery

### Backup Rancher Data

Rancher stores data in etcd. Backup your cluster's etcd for disaster recovery.

### Backup Configuration

Export your Terraform state and configuration:

```bash
# Backup terraform state
terraform state pull > rancher-state-backup.json

# Backup configuration
cp environments/manager/terraform.tfvars rancher-config-backup.tfvars
```

## Uninstalling Rancher

To remove Rancher:

```bash
terraform destroy -var-file="../environments/manager/terraform.tfvars"
```

**Warning**: This will delete all Rancher data and managed cluster configurations.

## Additional Resources

- [Rancher Documentation](https://rancher.com/docs/)
- [Rancher GitHub](https://github.com/rancher/rancher)
- [cert-manager Documentation](https://cert-manager.io/docs/)

## Support

For issues specific to this Terraform module, check the repository issues.
For Rancher-specific issues, consult the [Rancher Forums](https://forums.rancher.com/).

