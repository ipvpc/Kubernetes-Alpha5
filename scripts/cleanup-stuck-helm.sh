#!/bin/bash

# Script to clean up stuck Helm releases
# Usage: ./scripts/cleanup-stuck-helm.sh [release-name] [namespace]

set -e

RELEASE_NAME=${1:-nginx-ingress}
NAMESPACE=${2:-ingress-nginx}

echo "=========================================="
echo "Cleaning up stuck Helm release: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo "=========================================="

# Check if release exists
if ! helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo "Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    exit 0
fi

echo "Step 1: Attempting to uninstall with --no-hooks..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --no-hooks --timeout 2m || true

echo "Step 2: Checking for remaining resources..."
if kubectl get all -n "$NAMESPACE" 2>/dev/null | grep -q "$RELEASE_NAME"; then
    echo "Found remaining resources, attempting to delete..."
    
    # Delete resources manually
    kubectl delete deployment -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 || true
    kubectl delete service -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 || true
    kubectl delete configmap -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 || true
    kubectl delete secret -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --force --grace-period=0 || true
fi

echo "Step 3: Removing finalizers from stuck resources..."
# Remove finalizers from resources that might be stuck
kubectl get all -n "$NAMESPACE" -o json | \
  jq -r '.items[] | select(.metadata.finalizers != null) | "\(.kind)/\(.metadata.name)"' | \
  while read resource; do
    if [ -n "$resource" ]; then
      echo "Removing finalizers from $resource..."
      kubectl patch "$resource" -n "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
    fi
  done

echo "Step 4: Force deleting namespace if stuck..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Patching namespace to remove finalizers..."
    kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
    kubectl delete namespace "$NAMESPACE" --force --grace-period=0 || true
fi

echo "Step 5: Final cleanup attempt..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout 1m || true

echo "=========================================="
echo "Cleanup completed!"
echo "If resources are still stuck, you may need to:"
echo "1. Check for finalizers: kubectl get all -n $NAMESPACE -o yaml | grep finalizers"
echo "2. Manually remove finalizers from stuck resources"
echo "3. Delete the namespace: kubectl delete namespace $NAMESPACE --force --grace-period=0"
echo "=========================================="

