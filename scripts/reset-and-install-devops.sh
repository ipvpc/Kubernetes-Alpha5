#!/bin/bash

# Reset and Reinstall DevOps Kubernetes Cluster with Calico and Network Isolation
# This script resets the cluster and reinstalls it with Calico and network isolation
# Usage: ./scripts/reset-and-install-devops.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "DevOps Cluster Reset and Reinstall"
echo "CNI: Calico"
echo "Network Isolation: Enabled"
echo "==========================================${NC}"

# Check if we're in the right directory
if [ ! -d "ansible" ]; then
    echo -e "${RED}Error: ansible directory not found. Please run from project root.${NC}"
    exit 1
fi

# Confirm reset
echo -e "${YELLOW}WARNING: This will completely reset the DevOps cluster!${NC}"
echo -e "${YELLOW}All data and workloads will be deleted.${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Reset cancelled.${NC}"
    exit 0
fi

# Step 1: Reset cluster
echo -e "${GREEN}Step 1: Resetting cluster...${NC}"
cd ansible
ansible-playbook playbooks/reset-cluster.yml -i inventory-devops.yml
cd ..

# Step 2: Wait a bit for cleanup
echo -e "${GREEN}Step 2: Waiting for cleanup to complete...${NC}"
sleep 10

# Step 3: Reinstall cluster
echo -e "${GREEN}Step 3: Installing cluster with Calico and network isolation...${NC}"
./scripts/install-devops-kubernetes.sh devops kubeadm

echo -e "${GREEN}=========================================="
echo "Cluster Reset and Reinstall Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${GREEN}Cluster Configuration:${NC}"
echo "  - CNI Plugin: Calico"
echo "  - Network Isolation: Enabled (default deny-all)"
echo "  - Pod Network CIDR: 10.245.0.0/16"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Verify cluster: kubectl get nodes"
echo "  2. Check Calico: kubectl get pods -n kube-system -l k8s-app=calico-node"
echo "  3. Check network policies: kubectl get networkpolicies -A"
echo "  4. To expose services, see: ansible/NETWORK_ISOLATION_GUIDE.md"
echo ""

