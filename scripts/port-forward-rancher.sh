#!/bin/bash

# Port forward script for Rancher access
# This allows accessing Rancher via HTTP on localhost without HTTPS
# Usage: ./scripts/port-forward-rancher.sh [port]

PORT=${1:-8080}
NAMESPACE="cattle-system"

# Try to find the actual service name
SERVICE=$(kubectl get services -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "rancher")

if [ -z "$SERVICE" ] || [ "$SERVICE" = "rancher" ]; then
    # Check if rancher service exists, otherwise try common names
    if kubectl get service "rancher" -n "$NAMESPACE" >/dev/null 2>&1; then
        SERVICE="rancher"
    elif kubectl get service "rancher-server" -n "$NAMESPACE" >/dev/null 2>&1; then
        SERVICE="rancher-server"
    else
        echo "Error: Could not find Rancher service in namespace $NAMESPACE"
        echo "Available services:"
        kubectl get services -n "$NAMESPACE"
        exit 1
    fi
fi

echo "=========================================="
echo "Port Forwarding Rancher"
echo "=========================================="
echo ""
echo "Service: $SERVICE"
echo "Namespace: $NAMESPACE"
echo "Port: $PORT"
echo ""
echo "Forwarding $SERVICE service to localhost:$PORT"
echo "Access Rancher at: http://localhost:$PORT"
echo ""
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

kubectl port-forward -n "$NAMESPACE" svc/"$SERVICE" "$PORT":80

