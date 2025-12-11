#!/bin/bash

# Script to check why Rancher isn't deployed
# Usage: ./scripts/check-rancher-deployment.sh

echo "=========================================="
echo "Rancher Deployment Status Check"
echo "=========================================="

echo ""
echo "1. Checking Terraform state..."
cd terraform 2>/dev/null || { echo "Error: terraform directory not found"; exit 1; }

echo ""
echo "2. Checking if Rancher module is in state:"
terraform state list | grep -E "module.rancher|rancher" || echo "   No Rancher resources in state"

echo ""
echo "3. Checking prerequisites:"
echo "   - Traefik (Ingress Controller):"
kubectl get pods -n traefik 2>/dev/null && echo "   ✓ Traefik is running" || echo "   ✗ Traefik not found"

echo ""
echo "   - cert-manager:"
kubectl get pods -n cert-manager 2>/dev/null && echo "   ✓ cert-manager is running" || echo "   ✗ cert-manager not found"

echo ""
echo "   - cert-manager CRDs:"
kubectl get crd clusterissuers.cert-manager.io 2>/dev/null && echo "   ✓ ClusterIssuer CRD exists" || echo "   ✗ ClusterIssuer CRD not found"

echo ""
echo "4. Checking Helm releases:"
helm list -A | grep -E "rancher|cert-manager" || echo "   No Rancher or cert-manager Helm releases found"

echo ""
echo "5. Checking Terraform variables:"
if [ -f "../environments/manager/terraform.tfvars" ]; then
    echo "   Checking manager environment config:"
    grep -E "enable_rancher|rancher_hostname" ../environments/manager/terraform.tfvars || echo "   Rancher config not found in tfvars"
else
    echo "   Manager tfvars file not found"
fi

echo ""
echo "6. Checking for deployment errors:"
echo "   Run: terraform plan -var-file='../environments/manager/terraform.tfvars'"
echo "   to see what Terraform plans to deploy"

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "If Rancher isn't deployed, check:"
echo "1. Is enable_rancher = true in terraform.tfvars?"
echo "2. Run: ./scripts/deploy.sh manager plan"
echo "3. Check if there are any errors in the plan"
echo "4. Run: ./scripts/deploy.sh manager apply"
echo ""
echo "=========================================="

