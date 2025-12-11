#!/bin/bash

# Quick service status check script
# Usage: ./scripts/check-services.sh

echo "=========================================="
echo "Service Status Check"
echo "=========================================="

echo ""
echo "1. Cluster Nodes:"
kubectl get nodes

echo ""
echo "2. Ingress Controller (Traefik):"
kubectl get pods -n traefik
kubectl get service -n traefik

echo ""
echo "3. cert-manager:"
kubectl get pods -n cert-manager
kubectl get clusterissuer 2>/dev/null || echo "No ClusterIssuer found"

echo ""
echo "4. Rancher:"
kubectl get pods -n cattle-system
echo ""
echo "   Services in cattle-system:"
kubectl get service -n cattle-system
echo ""
echo "   Ingress:"
kubectl get ingress -n cattle-system 2>/dev/null || echo "   No Ingress found"

echo ""
echo "5. Access Information:"
echo "   Ingress Controller IP:"
kubectl get service traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}' 2>/dev/null || \
kubectl get service traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' 2>/dev/null || \
echo "   (Pending or using NodePort)"

echo ""
echo "   Rancher Access:"
RANCHER_SERVICE=$(kubectl get services -n cattle-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
RANCHER_HOST=$(kubectl get ingress -n cattle-system -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "$RANCHER_SERVICE" ]; then
    echo "   - Service: $RANCHER_SERVICE"
    if [ -n "$RANCHER_HOST" ]; then
        echo "   - Hostname: $RANCHER_HOST"
        echo "   - HTTP:  http://$RANCHER_HOST"
        echo "   - HTTPS: https://$RANCHER_HOST"
    else
        echo "   - Ingress not configured"
        echo "   - Use port-forward: kubectl port-forward -n cattle-system svc/$RANCHER_SERVICE 8080:80"
        echo "   - Then access: http://localhost:8080"
    fi
else
    echo "   - Rancher service not found. Deployment may be in progress or failed."
    echo "   - Check pods: kubectl get pods -n cattle-system"
fi

echo ""
echo "=========================================="

