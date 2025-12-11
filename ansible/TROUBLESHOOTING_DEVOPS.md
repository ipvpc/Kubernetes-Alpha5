# Troubleshooting DevOps Cluster Installation

## Common Error: "malformed header: missing HTTP content-type"

This error typically occurs during `kubeadm init` when containerd's CRI interface is not properly configured.

### Root Causes

1. **Incomplete containerd configuration** - The containerd config.toml is missing required CRI plugin settings
2. **Pause image version mismatch** - Using an older pause image version
3. **Containerd not fully ready** - Containerd service started but CRI interface not ready

### Fixes Applied

The playbook has been updated to:

1. **Generate proper containerd config** using `containerd config default`
2. **Update pause image** to version 3.9 (matching Kubernetes 1.28)
3. **Enable SystemdCgroup** for proper cgroup management
4. **Install cri-tools** for debugging
5. **Verify containerd** before kubeadm init
6. **Pre-pull images** to avoid network issues during init

### Manual Fix (if playbook still fails)

If the error persists, you can manually fix containerd configuration:

```bash
# SSH into the master node
ssh support@192.168.10.73

# Generate default containerd config
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Update pause image to 3.9
sudo sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml

# Ensure SystemdCgroup is enabled
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify containerd is working
sudo crictl --runtime-endpoint=unix:///var/run/containerd/containerd.sock version

# Reset and retry kubeadm init
sudo kubeadm reset --force --cri-socket=unix:///var/run/containerd/containerd.sock
sudo kubeadm init --pod-network-cidr=10.245.0.0/16 --service-cidr=10.96.0.0/12 --control-plane-endpoint=192.168.10.73:6443 --upload-certs --cri-socket=unix:///var/run/containerd/containerd.sock
```

### Verify Containerd Configuration

Check that containerd is properly configured:

```bash
# Check containerd status
sudo systemctl status containerd

# Test CRI interface
sudo crictl --runtime-endpoint=unix:///var/run/containerd/containerd.sock version

# Check pause image
sudo crictl --runtime-endpoint=unix:///var/run/containerd/containerd.sock images | grep pause
```

### Partial Initialization Recovery

If kubeadm init fails but partially initializes:

```bash
# Check what was created
ls -la /etc/kubernetes/

# If admin.conf exists, cluster may be usable
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Check cluster status
kubectl get nodes

# If nodes are Ready, manually deploy CoreDNS
kubectl apply -f https://github.com/coredns/coredns/releases/download/v1.10.1/coredns.yaml
```

### Network Issues

If images fail to pull:

```bash
# Pre-pull all required images
sudo kubeadm config images pull --kubernetes-version=1.28.0 --cri-socket=unix:///var/run/containerd/containerd.sock

# Check image registry accessibility
curl -I https://registry.k8s.io/v2/
```

### Additional Debugging

Enable verbose output:

```bash
# Run kubeadm init with verbose logging
sudo kubeadm init \
  --pod-network-cidr=10.245.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --control-plane-endpoint=192.168.10.73:6443 \
  --upload-certs \
  --cri-socket=unix:///var/run/containerd/containerd.sock \
  --v=5
```

Check containerd logs:

```bash
sudo journalctl -u containerd -n 100
sudo journalctl -u kubelet -n 100
```

### Re-running the Playbook

After fixing containerd manually, you can re-run the playbook:

```bash
# From project root
./scripts/install-devops-kubernetes.sh devops kubeadm
```

Or reset everything and start fresh:

```bash
# On master node
sudo kubeadm reset --force --cri-socket=unix:///var/run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd /etc/cni/net.d

# Then re-run playbook
```

