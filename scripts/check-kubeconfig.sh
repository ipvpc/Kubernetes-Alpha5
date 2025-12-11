#!/bin/bash

# Script to check kubeconfig and cluster connectivity
# Usage: ./scripts/check-kubeconfig.sh [kubeconfig-path]

KUBECONFIG_PATH=${1:-"~/.kube/config-manager"}

echo "=========================================="
echo "Kubeconfig and Cluster Connectivity Check"
echo "=========================================="
echo ""

# Expand ~ if present
if [[ "$KUBECONFIG_PATH" == ~* ]]; then
    KUBECONFIG_PATH="${KUBECONFIG_PATH/#\~/$HOME}"
fi

echo "1. Checking if kubeconfig file exists:"
if [ -f "$KUBECONFIG_PATH" ]; then
    echo "   ✓ File exists: $KUBECONFIG_PATH"
else
    echo "   ✗ File NOT found: $KUBECONFIG_PATH"
    echo "   Please check the path or create the kubeconfig file"
    exit 1
fi

echo ""
echo "2. Checking kubeconfig structure:"
if kubectl --kubeconfig="$KUBECONFIG_PATH" config view >/dev/null 2>&1; then
    echo "   ✓ Kubeconfig is valid"
else
    echo "   ✗ Kubeconfig is invalid or corrupted"
    exit 1
fi

echo ""
echo "3. Current context:"
kubectl --kubeconfig="$KUBECONFIG_PATH" config current-context 2>/dev/null || echo "   No current context set"

echo ""
echo "4. Available contexts:"
kubectl --kubeconfig="$KUBECONFIG_PATH" config get-contexts

echo ""
echo "5. API Server endpoint:"
kubectl --kubeconfig="$KUBECONFIG_PATH" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null
echo ""

echo ""
echo "6. Testing cluster connectivity:"
if kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info >/dev/null 2>&1; then
    echo "   ✓ Cluster is reachable"
    kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info
else
    echo "   ✗ Cannot reach cluster"
    echo "   Error details:"
    kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info 2>&1 || true
    echo ""
    echo "   Troubleshooting:"
    echo "   - Check if the API server endpoint is correct"
    echo "   - Verify network connectivity to the cluster"
    echo "   - Ensure firewall rules allow access to port 6443"
    echo "   - Check if you're using the correct kubeconfig file"
fi

echo ""
echo "7. Testing authentication:"
if kubectl --kubeconfig="$KUBECONFIG_PATH" get nodes >/dev/null 2>&1; then
    echo "   ✓ Authentication successful"
    echo "   Nodes:"
    kubectl --kubeconfig="$KUBECONFIG_PATH" get nodes
else
    echo "   ✗ Authentication failed"
    kubectl --kubeconfig="$KUBECONFIG_PATH" get nodes 2>&1 || true
fi

echo ""
echo "=========================================="

