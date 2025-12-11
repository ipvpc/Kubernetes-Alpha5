#!/bin/bash

# Verification script for Kubernetes deployment
# Checks that all services are running properly

set -e

ENVIRONMENT=${1:-manager}

echo "=========================================="
echo "Verifying Deployment: $ENVIRONMENT"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_namespace() {
    local namespace=$1
    if kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Namespace '$namespace' exists"
        return 0
    else
        echo -e "${RED}✗${NC} Namespace '$namespace' not found"
        return 1
    fi
}

check_pods() {
    local namespace=$1
    local label_selector=${2:-""}
    
    if [ -z "$label_selector" ]; then
        local pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
        local running=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    else
        local pods=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | wc -l)
        local running=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    fi
    
    if [ "$pods" -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} No pods found in namespace '$namespace'"
        return 1
    elif [ "$running" -eq "$pods" ]; then
        echo -e "${GREEN}✓${NC} All pods running in '$namespace' ($running/$pods)"
        return 0
    else
        echo -e "${RED}✗${NC} Some pods not running in '$namespace' ($running/$pods running)"
        kubectl get pods -n "$namespace" | grep -v Running || true
        return 1
    fi
}

check_service() {
    local namespace=$1
    local service=$2
    
    if kubectl get service "$service" -n "$namespace" &>/dev/null; then
        local endpoints=$(kubectl get endpoints "$service" -n "$namespace" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | wc -w)
        if [ "$endpoints" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} Service '$service' in '$namespace' has endpoints"
            return 0
        else
            echo -e "${YELLOW}⚠${NC} Service '$service' in '$namespace' has no endpoints"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Service '$service' not found in '$namespace'"
        return 1
    fi
}

check_ingress() {
    local namespace=$1
    
    if kubectl get ingress -n "$namespace" &>/dev/null; then
        local ingresses=$(kubectl get ingress -n "$namespace" --no-headers 2>/dev/null | wc -l)
        if [ "$ingresses" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} Ingress resources found in '$namespace'"
            kubectl get ingress -n "$namespace"
            return 0
        else
            echo -e "${YELLOW}⚠${NC} No ingress resources in '$namespace'"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠${NC} No ingress resources in '$namespace'"
        return 1
    fi
}

# Check cluster connectivity
echo ""
echo "1. Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓${NC} Cluster is accessible"
    kubectl get nodes
else
    echo -e "${RED}✗${NC} Cannot connect to cluster"
    exit 1
fi

# Check Ingress Controller
echo ""
echo "2. Checking Ingress Controller..."
if check_namespace "ingress-nginx"; then
    check_pods "ingress-nginx" "app.kubernetes.io/name=ingress-nginx"
    check_service "ingress-nginx" "ingress-nginx-controller"
    
    # Get ingress controller external IP
    echo ""
    echo "   Ingress Controller External IP:"
    kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}' || \
    kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' || \
    echo "   (No external IP assigned yet - may be pending)"
fi

# Check cert-manager
echo ""
echo "3. Checking cert-manager..."
if check_namespace "cert-manager"; then
    check_pods "cert-manager"
    
    # Check ClusterIssuer
    echo ""
    echo "   Checking ClusterIssuer..."
    if kubectl get clusterissuer &>/dev/null; then
        kubectl get clusterissuer
        echo -e "${GREEN}✓${NC} ClusterIssuer configured"
    else
        echo -e "${YELLOW}⚠${NC} No ClusterIssuer found"
    fi
fi

# Check Rancher
echo ""
echo "4. Checking Rancher..."
if check_namespace "cattle-system"; then
    check_pods "cattle-system" "app=rancher"
    check_service "cattle-system" "rancher"
    
    # Check Rancher ingress
    echo ""
    echo "   Checking Rancher Ingress..."
    check_ingress "cattle-system"
    
    # Get Rancher URL
    echo ""
    echo "   Rancher Access:"
    local rancher_host=$(kubectl get ingress -n cattle-system -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not configured")
    if [ "$rancher_host" != "Not configured" ]; then
        echo "   - Hostname: $rancher_host"
        echo "   - HTTP:  http://$rancher_host"
        echo "   - HTTPS: https://$rancher_host"
    else
        echo "   - Ingress not configured yet"
    fi
fi

# Check for HTTP access (non-HTTPS)
echo ""
echo "5. Checking HTTP/HTTPS Configuration..."
if kubectl get ingress -n cattle-system &>/dev/null; then
    local tls_enabled=$(kubectl get ingress -n cattle-system -o jsonpath='{.items[0].spec.tls[*].hosts[0]}' 2>/dev/null || echo "")
    if [ -n "$tls_enabled" ]; then
        echo -e "${GREEN}✓${NC} TLS/HTTPS is configured"
    else
        echo -e "${YELLOW}⚠${NC} TLS/HTTPS not configured - using HTTP only"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "To access services:"
echo "1. Get ingress controller IP:"
echo "   kubectl get service ingress-nginx-controller -n ingress-nginx"
echo ""
echo "2. For Rancher (if configured):"
echo "   kubectl get ingress -n cattle-system"
echo ""
echo "3. Port forward for local access (if needed):"
echo "   kubectl port-forward -n cattle-system svc/rancher 8080:80"
echo "   Then access: http://localhost:8080"
echo ""
echo "=========================================="

