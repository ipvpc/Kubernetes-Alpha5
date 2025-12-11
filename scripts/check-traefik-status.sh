#!/bin/bash

# Quick script to check Traefik deployment status
# Usage: ./scripts/check-traefik-status.sh

NAMESPACE="traefik"

echo "=========================================="
echo "Traefik Deployment Status"
echo "=========================================="

echo ""
echo "1. Checking Traefik pods:"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "2. Checking pod status details:"
kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null || echo "No pods found"

echo ""
echo "3. Checking for pending pods:"
PENDING=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PENDING" -gt 0 ]; then
    echo "   ⚠ Found $PENDING pending pod(s):"
    kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending
    echo ""
    echo "   Checking why pods are pending:"
    kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.conditions[*].message}{"\n"}{end}' 2>/dev/null
fi

echo ""
echo "4. Checking for failed pods:"
FAILED=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$FAILED" -gt 0 ]; then
    echo "   ✗ Found $FAILED failed pod(s):"
    kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed
fi

echo ""
echo "5. Checking recent events:"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10

echo ""
echo "6. Checking pod logs (if any pods exist):"
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$FIRST_POD" ]; then
    echo "   Logs from $FIRST_POD:"
    kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=20 2>/dev/null || echo "   Could not retrieve logs"
else
    echo "   No pods found to check logs"
fi

echo ""
echo "7. Checking Helm release status:"
helm status traefik -n "$NAMESPACE" 2>/dev/null || echo "   Helm release not found or not ready"

echo ""
echo "=========================================="
echo "Common Issues:"
echo "=========================================="
echo ""
echo "If pods are Pending:"
echo "  - Check node resources: kubectl describe nodes"
echo "  - Check resource requests: kubectl describe pod -n $NAMESPACE"
echo ""
echo "If pods are CrashLoopBackOff:"
echo "  - Check logs: kubectl logs -n $NAMESPACE <pod-name>"
echo "  - Check events: kubectl describe pod -n $NAMESPACE <pod-name>"
echo ""
echo "If image pull errors:"
echo "  - Check network connectivity"
echo "  - Verify image registry access"
echo ""
echo "=========================================="

