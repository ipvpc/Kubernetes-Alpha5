#!/bin/bash

# Script to clean up stuck namespaces
# Usage: ./scripts/cleanup-stuck-namespace.sh [namespace]

set -e

NAMESPACE=${1:-ingress-nginx}

echo "=========================================="
echo "Cleaning up stuck namespace: $NAMESPACE"
echo "=========================================="

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' does not exist or is already deleted."
    exit 0
fi

echo ""
echo "Step 1: Checking namespace status..."
kubectl get namespace "$NAMESPACE" -o yaml | grep -A 5 "status:" || true

echo ""
echo "Step 2: Removing finalizers from namespace..."
kubectl get namespace "$NAMESPACE" -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw /api/v1/namespaces/$NAMESPACE/finalize -f - || \
  kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge || true

echo ""
echo "Step 3: Removing finalizers from all resources in namespace..."

# Get all resource types in the namespace
RESOURCE_TYPES=$(kubectl api-resources --verbs=list --namespaced -o name)

for resource_type in $RESOURCE_TYPES; do
    echo "   Checking $resource_type..."
    RESOURCES=$(kubectl get "$resource_type" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | "\(.kind)/\(.metadata.name)"' 2>/dev/null || echo "")
    
    if [ -n "$RESOURCES" ]; then
        echo "$RESOURCES" | while read -r resource; do
            if [ -n "$resource" ]; then
                KIND=$(echo "$resource" | cut -d'/' -f1)
                NAME=$(echo "$resource" | cut -d'/' -f2)
                echo "     Removing finalizers from $KIND/$NAME..."
                kubectl patch "$KIND" "$NAME" -n "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            fi
        done
    fi
done

echo ""
echo "Step 4: Force deleting namespace..."
kubectl delete namespace "$NAMESPACE" --force --grace-period=0 --timeout=30s 2>/dev/null || true

echo ""
echo "Step 5: Waiting for namespace to be deleted..."
sleep 5

# Check if namespace still exists
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "⚠ Namespace still exists. Trying one more time..."
    kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge
    kubectl delete namespace "$NAMESPACE" --force --grace-period=0
    sleep 3
fi

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace still stuck. Manual intervention may be required."
    echo ""
    echo "Try these commands manually:"
    echo "  kubectl get namespace $NAMESPACE -o yaml"
    echo "  kubectl patch namespace $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
    echo "  kubectl delete namespace $NAMESPACE --force --grace-period=0"
    exit 1
else
    echo "✓ Namespace '$NAMESPACE' has been deleted successfully!"
fi

echo ""
echo "=========================================="

