#!/bin/bash

# Port forward script for Rancher access
# This allows accessing Rancher via HTTP on localhost without HTTPS
# Usage: ./scripts/port-forward-rancher.sh [port]

PORT=${1:-8080}
NAMESPACE="cattle-system"
SERVICE="rancher"

echo "=========================================="
echo "Port Forwarding Rancher"
echo "=========================================="
echo ""
echo "Forwarding $SERVICE service to localhost:$PORT"
echo "Access Rancher at: http://localhost:$PORT"
echo ""
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

kubectl port-forward -n "$NAMESPACE" svc/"$SERVICE" "$PORT":80

