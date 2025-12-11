#!/bin/bash

# Script to find Rancher service name and access information
# Usage: ./scripts/find-rancher-service.sh

echo "=========================================="
echo "Finding Rancher Service"
echo "=========================================="

NAMESPACE="cattle-system"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' not found. Rancher may not be deployed yet."
    echo ""
    echo "To deploy Rancher, run:"
    echo "  ./scripts/deploy.sh manager apply"
    exit 1
fi

echo ""
echo "1. Checking for Rancher pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "2. Checking for all services in cattle-system namespace:"
kubectl get services -n "$NAMESPACE"

echo ""
echo "3. Checking Helm releases:"
helm list -n "$NAMESPACE"

echo ""
echo "4. Checking for Rancher deployment:"
kubectl get deployment -n "$NAMESPACE"

echo ""
echo "5. Service details (if found):"
SERVICE_NAME=$(kubectl get services -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SERVICE_NAME" ]; then
    echo "   Found service: $SERVICE_NAME"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"
    echo ""
    echo "   To port-forward:"
    echo "   kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8080:80"
else
    echo "   No services found in $NAMESPACE namespace"
fi

echo ""
echo "6. Checking ingress:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "   No ingress found"

echo ""
echo "=========================================="

