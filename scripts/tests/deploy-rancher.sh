#!/bin/bash

# Quick script to check and deploy Rancher
# Usage: ./scripts/deploy-rancher.sh

ENVIRONMENT=${1:-manager}

echo "=========================================="
echo "Rancher Deployment Check"
echo "=========================================="

echo ""
echo "1. Checking prerequisites..."

# Check Traefik
echo "   - Traefik Ingress:"
if kubectl get pods -n traefik >/dev/null 2>&1; then
    TRAEFIK_PODS=$(kubectl get pods -n traefik --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$TRAEFIK_PODS" -gt 0 ]; then
        echo "   ✓ Traefik is running ($TRAEFIK_PODS pods)"
    else
        echo "   ✗ Traefik pods not running"
        echo "   Deploy Traefik first: ./scripts/deploy.sh $ENVIRONMENT apply"
        exit 1
    fi
else
    echo "   ✗ Traefik namespace not found"
    echo "   Deploy Traefik first: ./scripts/deploy.sh $ENVIRONMENT apply"
    exit 1
fi

# Check cert-manager
echo "   - cert-manager:"
if kubectl get pods -n cert-manager >/dev/null 2>&1; then
    CERT_MGR_PODS=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$CERT_MGR_PODS" -gt 0 ]; then
        echo "   ✓ cert-manager is running ($CERT_MGR_PODS pods)"
    else
        echo "   ⚠ cert-manager namespace exists but pods not running"
    fi
else
    echo "   ⚠ cert-manager not deployed yet (will be deployed with Rancher)"
fi

echo ""
echo "2. Checking Rancher configuration..."
if [ -f "environments/$ENVIRONMENT/terraform.tfvars" ]; then
    ENABLE_RANCHER=$(grep "^enable_rancher" "environments/$ENVIRONMENT/terraform.tfvars" | grep -o "true\|false" || echo "not found")
    if [ "$ENABLE_RANCHER" = "true" ]; then
        echo "   ✓ Rancher is enabled in configuration"
    else
        echo "   ✗ Rancher is disabled (enable_rancher = false)"
        echo "   Edit environments/$ENVIRONMENT/terraform.tfvars and set enable_rancher = true"
        exit 1
    fi
else
    echo "   ✗ Configuration file not found: environments/$ENVIRONMENT/terraform.tfvars"
    exit 1
fi

echo ""
echo "3. Checking Terraform state..."
cd terraform 2>/dev/null || { echo "Error: terraform directory not found"; exit 1; }

RANCHER_IN_STATE=$(terraform state list 2>/dev/null | grep -c "module.rancher" || echo "0")
if [ "$RANCHER_IN_STATE" -gt 0 ]; then
    echo "   ✓ Rancher resources found in Terraform state"
    echo "   Checking deployment status..."
    kubectl get pods -n cattle-system 2>/dev/null || echo "   ⚠ No pods in cattle-system namespace"
else
    echo "   ⚠ Rancher not in Terraform state yet"
    echo "   This means Rancher hasn't been deployed"
fi

echo ""
echo "=========================================="
echo "To Deploy Rancher:"
echo "=========================================="
echo ""
echo "1. Plan the deployment:"
echo "   ./scripts/deploy.sh $ENVIRONMENT plan"
echo ""
echo "2. Apply the deployment:"
echo "   ./scripts/deploy.sh $ENVIRONMENT apply"
echo ""
echo "This will deploy:"
echo "  - cert-manager (if not already deployed)"
echo "  - Rancher (after prerequisites are ready)"
echo ""
echo "Expected duration: 5-10 minutes"
echo "=========================================="

