#!/bin/bash

# Script to check what Helm is waiting for
# Usage: ./scripts/check-helm-wait-status.sh

RELEASE="traefik"
NAMESPACE="traefik"

echo "=========================================="
echo "Checking Helm Wait Status for $RELEASE"
echo "=========================================="

echo ""
echo "1. Helm release status:"
helm status "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "   Release not found or not ready"

echo ""
echo "2. Checking pods readiness:"
kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[] | "\(.metadata.name): Ready=\(.status.containerStatuses[0].ready // "false"), Phase=\(.status.phase)"' 2>/dev/null || \
kubectl get pods -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,PHASE:.status.phase

echo ""
echo "3. Checking readiness probes:"
kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[] | "\(.metadata.name):\n  Readiness: \(.spec.containers[0].readinessProbe // "none")\n  Liveness: \(.spec.containers[0].livenessProbe // "none")"' 2>/dev/null || echo "   Could not check probes"

echo ""
echo "4. Checking pod conditions:"
kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[] | "\(.metadata.name):\n  \(.status.conditions[] | "\(.type): \(.status) - \(.message // "no message")")"' 2>/dev/null || echo "   Could not check conditions"

echo ""
echo "5. If pods are running but Helm is still waiting:"
echo "   Helm might be waiting for readiness probes to pass"
echo "   You can check if Traefik is actually working:"
echo "   kubectl port-forward -n $NAMESPACE svc/traefik 8080:80"
echo "   Then try: curl http://localhost:8080"

echo ""
echo "=========================================="


