# DevOps Kubernetes Cluster Setup

This guide explains how to create a Kubernetes cluster named "devops" using Ansible.

## Prerequisites

1. Ansible installed (version 2.9 or higher)
2. SSH access to all target nodes configured
3. Inventory file configured at `ansible/inventory-devops.yml`
4. Python 3 installed on all target nodes

## Quick Start

### Option 1: Using the Installation Script (Recommended)

```bash
# From the project root directory
./scripts/install-devops-kubernetes.sh devops kubeadm
```

Or for k3s:
```bash
./scripts/install-devops-kubernetes.sh devops k3s
```

### Option 2: Using Ansible Playbook Directly

```bash
cd ansible

# For kubeadm installation
ansible-playbook playbooks/devops-cluster.yml -i inventory-devops.yml

# For k3s installation (update install_method in inventory-devops.yml first)
ansible-playbook playbooks/devops-cluster.yml -i inventory-devops.yml
```

## Inventory Configuration

The inventory file `ansible/inventory-devops.yml` should be configured with your nodes:

```yaml
all:
  vars:
    ansible_user: support
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    ansible_python_interpreter: /usr/bin/python3
    kubernetes_version: "1.28.0"
    container_runtime: "containerd"
    pod_network_cidr: "10.245.0.0/16"
    install_method: "kubeadm"  # or "k3s"
  
  children:
    control_plane:
      hosts:
        master1:
          ansible_host: 192.168.10.73
          node_name: devops1
    
    workers:
      hosts:
        worker1:
          ansible_host: 192.168.10.74
          node_name: devops2
        worker2:
          ansible_host: 192.168.10.75
          node_name: devops3
```

## What the Playbook Does

1. **Pre-installation Tasks**:
   - Disables swap
   - Configures kernel modules
   - Sets up networking (IP forwarding, bridge networking)
   - Installs required packages

2. **Container Runtime Installation**:
   - Installs and configures containerd

3. **Kubernetes Installation**:
   - Installs kubeadm, kubelet, and kubectl
   - Initializes the cluster on the first control plane node
   - Joins additional control plane nodes (if any)
   - Joins worker nodes

4. **CNI Plugin Installation**:
   - Installs Flannel or Calico network plugin

5. **Post-installation**:
   - Configures kubeconfig
   - Verifies cluster status

## Accessing the Cluster

After installation, retrieve the kubeconfig:

```bash
# Get kubeconfig from master node
FIRST_MASTER=$(ansible-inventory -i ansible/inventory-devops.yml --list | jq -r '.control_plane.hosts[0]')
ansible $FIRST_MASTER -i ansible/inventory-devops.yml -m fetch \
  -a "src=/root/.kube/config dest=~/.kube/config-devops flat=yes" \
  --become

# Set KUBECONFIG
export KUBECONFIG=~/.kube/config-devops

# Verify cluster
kubectl get nodes
```

## Troubleshooting

### Check Ansible connectivity
```bash
ansible all -i ansible/inventory-devops.yml -m ping
```

### Check playbook syntax
```bash
ansible-playbook ansible/playbooks/devops-cluster.yml -i ansible/inventory-devops.yml --syntax-check
```

### Run in check mode (dry-run)
```bash
ansible-playbook ansible/playbooks/devops-cluster.yml -i ansible/inventory-devops.yml --check
```

### View verbose output
```bash
ansible-playbook ansible/playbooks/devops-cluster.yml -i ansible/inventory-devops.yml -v
```

## Customization

You can customize the cluster by modifying variables in:
- `ansible/inventory-devops.yml` - Cluster-specific variables
- `ansible/group_vars/all.yml` - Global variables for all clusters

## Support

For issues or questions, refer to:
- `KUBERNETES_INSTALLATION.md` - General Kubernetes installation guide
- `INSTALL.md` - Installation instructions

