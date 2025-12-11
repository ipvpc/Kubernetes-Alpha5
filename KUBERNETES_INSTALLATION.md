# Automated Kubernetes Installation Guide

This guide explains how to automatically install Kubernetes on remote hosts before deploying Rancher.

## Overview

This automation uses Ansible to install Kubernetes on remote hosts. It supports multiple installation methods:

- **kubeadm**: Standard Kubernetes installation (recommended for production)
- **k3s**: Lightweight Kubernetes distribution (ideal for edge/dev environments)
- **RKE2**: Rancher Kubernetes Engine 2 (coming soon)

## Prerequisites

1. **Ansible**: Version 2.9+ installed
   ```bash
   pip install ansible
   # or
   pip3 install ansible
   ```

2. **SSH Access**: Passwordless SSH access to all remote hosts
   ```bash
   ssh-copy-id user@remote-host
   ```

3. **Python**: Python 3.x installed on all remote hosts

4. **Sudo Access**: Your SSH user must have sudo privileges on remote hosts

5. **System Requirements**:
   - Minimum 2 CPU cores per node
   - Minimum 2GB RAM per node
   - Ubuntu 20.04+ or CentOS 7+/RHEL 8+
   - Swap disabled (will be done automatically)

## Quick Start

### 1. Configure Inventory

Copy the example inventory and configure your hosts:

```bash
cp ansible/inventory.example.yml ansible/inventory.yml
```

Edit `ansible/inventory.yml`:

```yaml
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    install_method: "kubeadm"  # or "k3s"
    
  children:
    control_plane:
      hosts:
        master1:
          ansible_host: 192.168.1.10
        master2:
          ansible_host: 192.168.1.11
        master3:
          ansible_host: 192.168.1.12
    
    workers:
      hosts:
        worker1:
          ansible_host: 192.168.1.20
        worker2:
          ansible_host: 192.168.1.21
```

### 2. Configure Installation Method

Edit `ansible/group_vars/all.yml` to customize:

```yaml
install_method: "kubeadm"  # or "k3s"
kubernetes_version: "1.28.0"
container_runtime: "containerd"
pod_network_cidr: "10.244.0.0/16"
cni_plugin: "flannel"  # or "calico"
```

### 3. Install Kubernetes

**Linux/Mac:**
```bash
./scripts/install-kubernetes.sh manager kubeadm
```

**Windows (PowerShell):**
```powershell
.\scripts\install-kubernetes.sh manager kubeadm
```

**Or manually with Ansible:**
```bash
cd ansible
ansible-playbook playbooks/kubeadm-install.yml -i inventory.yml
```

### 4. Verify Installation

After installation, the script will download the kubeconfig. Verify the cluster:

```bash
export KUBECONFIG=~/.kube/config-manager
kubectl get nodes
```

### 5. Deploy Rancher

Once Kubernetes is installed, you can deploy Rancher:

```bash
./scripts/deploy.sh manager apply
```

## Installation Methods

### kubeadm (Recommended for Production)

**Pros:**
- Standard Kubernetes distribution
- Full feature set
- Best for production workloads
- Supports HA multi-master setup

**Cons:**
- More resource-intensive
- Requires more configuration

**Usage:**
```bash
./scripts/install-kubernetes.sh manager kubeadm
```

### k3s (Lightweight)

**Pros:**
- Lightweight and fast
- Single binary installation
- Ideal for edge/dev environments
- Lower resource requirements

**Cons:**
- Some Kubernetes features may differ
- Less suitable for large-scale production

**Usage:**
```bash
./scripts/install-kubernetes.sh manager k3s
```

## Configuration Options

### Inventory Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ansible_user` | SSH user for remote hosts | `ubuntu` |
| `ansible_ssh_private_key_file` | Path to SSH private key | `~/.ssh/id_rsa` |
| `install_method` | Installation method | `kubeadm` |

### Group Variables (`ansible/group_vars/all.yml`)

| Variable | Description | Default |
|----------|-------------|---------|
| `kubernetes_version` | Kubernetes version | `1.28.0` |
| `container_runtime` | Container runtime | `containerd` |
| `pod_network_cidr` | Pod network CIDR | `10.244.0.0/16` |
| `service_cidr` | Service CIDR | `10.96.0.0/12` |
| `cni_plugin` | CNI plugin | `flannel` |
| `disable_swap` | Disable swap | `true` |
| `configure_firewall` | Configure firewall | `true` |

## Architecture

### Single Master Setup

For development/testing, you can use a single-node cluster:

```yaml
all:
  children:
    single_node:
      hosts:
        node1:
          ansible_host: 192.168.1.10
      vars:
        is_control_plane: true
        is_worker: true
```

### High Availability Setup

For production, use multiple control plane nodes:

```yaml
control_plane:
  hosts:
    master1:
      ansible_host: 192.168.1.10
    master2:
      ansible_host: 192.168.1.11
    master3:
      ansible_host: 192.168.1.12
```

## Troubleshooting

### Issue: Ansible connection fails

**Check SSH access:**
```bash
ansible all -i ansible/inventory.yml -m ping
```

**Verify SSH key:**
```bash
ssh -i ~/.ssh/id_rsa user@remote-host
```

### Issue: Kubernetes installation fails

**Check system requirements:**
```bash
ansible all -i ansible/inventory.yml -m shell -a "free -h && nproc"
```

**Verify swap is disabled:**
```bash
ansible all -i ansible/inventory.yml -m shell -a "swapon --show"
```

### Issue: Nodes not joining cluster

**Check kubelet status:**
```bash
ansible all -i ansible/inventory.yml -m shell -a "systemctl status kubelet" --become
```

**View kubelet logs:**
```bash
ansible all -i ansible/inventory.yml -m shell -a "journalctl -u kubelet -n 50" --become
```

### Issue: CNI plugin not working

**Check CNI pods:**
```bash
kubectl get pods -n kube-flannel  # for Flannel
kubectl get pods -n kube-system -l k8s-app=calico-node  # for Calico
```

**Check node status:**
```bash
kubectl get nodes
kubectl describe node <node-name>
```

## Manual Installation Steps

If you prefer to install manually or troubleshoot:

### kubeadm Manual Steps

1. **Prepare nodes:**
   ```bash
   # Disable swap
   swapoff -a
   sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
   
   # Load kernel modules
   modprobe overlay
   modprobe br_netfilter
   
   # Configure sysctl
   cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   EOF
   sudo sysctl --system
   ```

2. **Install containerd:**
   ```bash
   # Follow official containerd installation guide
   ```

3. **Install kubeadm, kubelet, kubectl:**
   ```bash
   # Follow official Kubernetes installation guide
   ```

4. **Initialize cluster (first master):**
   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16
   ```

5. **Join nodes:**
   ```bash
   # Use the join command from kubeadm init output
   sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
   ```

### k3s Manual Steps

1. **Install k3s server (first master):**
   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. **Get token:**
   ```bash
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```

3. **Install k3s agent (workers):**
   ```bash
   curl -sfL https://get.k3s.io | K3S_URL=https://<master-ip>:6443 K3S_TOKEN=<token> sh -
   ```

## Security Considerations

1. **SSH Keys**: Use SSH keys instead of passwords
2. **Firewall**: Configure firewall rules (done automatically)
3. **RBAC**: Kubernetes RBAC is enabled by default
4. **Network Policies**: Consider implementing network policies
5. **Updates**: Keep Kubernetes and system packages updated

## Next Steps

After Kubernetes is installed:

1. **Verify cluster:**
   ```bash
   kubectl get nodes
   kubectl cluster-info
   ```

2. **Deploy Rancher:**
   ```bash
   ./scripts/deploy.sh manager apply
   ```

3. **Configure kubectl context:**
   ```bash
   # Update terraform.tfvars with kubeconfig path
   kubeconfig_path = "~/.kube/config-manager"
   ```

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Installation Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [k3s Documentation](https://k3s.io/)
- [Ansible Documentation](https://docs.ansible.com/)

## Support

For issues:
1. Check the troubleshooting section above
2. Review Ansible playbook logs
3. Check Kubernetes component logs on remote hosts
4. Consult Kubernetes and Ansible documentation
