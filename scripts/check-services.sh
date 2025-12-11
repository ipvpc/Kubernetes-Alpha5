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
echo "2. Ingress Controller:"
kubectl get pods -n ingress-nginx
kubectl get service -n ingress-nginx

echo ""
echo "3. cert-manager:"
kubectl get pods -n cert-manager
kubectl get clusterissuer 2>/dev/null || echo "No ClusterIssuer found"

echo ""
echo "4. Rancher:"
kubectl get pods -n cattle-system
kubectl get service -n cattle-system
kubectl get ingress -n cattle-system 2>/dev/null || echo "No Ingress found"

echo ""
echo "5. Access Information:"
echo "   Ingress Controller IP:"
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}' 2>/dev/null || \
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' 2>/dev/null || \
echo "   (Pending or using NodePort)"

echo ""
echo "   Rancher Access (if configured):"
RANCHER_HOST=$(kubectl get ingress -n cattle-system -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
if [ -n "$RANCHER_HOST" ]; then
    echo "   - Hostname: $RANCHER_HOST"
    echo "   - HTTP:  http://$RANCHER_HOST"
    echo "   - HTTPS: https://$RANCHER_HOST"
else
    echo "   - Not configured via Ingress"
    echo "   - Use port-forward: kubectl port-forward -n cattle-system svc/rancher 8080:80"
    echo "   - Then access: http://localhost:8080"
fi

echo ""
echo "=========================================="

