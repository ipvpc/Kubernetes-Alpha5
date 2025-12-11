#!/bin/bash

# Script to get Kubernetes node IPs
# Usage: ./scripts/get-node-ips.sh

echo "=========================================="
echo "Kubernetes Node IPs"
echo "=========================================="
echo ""

echo "Internal IPs (for externalIPs configuration):"
kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null

echo ""
echo "External IPs (if available):"
kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}' 2>/dev/null

echo ""
echo "All node addresses:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address,EXTERNAL-IP:.status.addresses[?(@.type=="ExternalIP")].address

echo ""
echo "=========================================="
echo "To use these IPs in terraform.tfvars, add:"
echo "=========================================="
echo ""
echo "ingress_external_ips = ["
kubectl get nodes -o jsonpath='{range .items[*]}{"  \"{.status.addresses[?(@.type==\"InternalIP\")].address}\",\n"}{end}' 2>/dev/null | sed '$ s/,$//'
echo "]"
echo ""
echo "=========================================="

