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

## Common Error: "connection to the server was refused"

This error occurs when kubectl cannot connect to the Kubernetes API server, usually because:

1. **API server not ready** - The API server pod hasn't started yet
2. **Wrong kubeconfig endpoint** - kubeconfig pointing to wrong IP/port
3. **API server only listening on localhost** - Not bound to external IP

### Quick Fix

```bash
# SSH into master node
ssh support@192.168.10.73

# Use admin.conf directly (always works on master)
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes

# If that works, copy it to the expected location
sudo cp /etc/kubernetes/admin.conf /root/.kube/config

# Check API server pod status
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l component=kube-apiserver

# Wait for API server to be ready
kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=ready pod -l component=kube-apiserver -n kube-system --timeout=300s

# Verify connectivity
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info
```

### Check API Server Status

```bash
# Check if API server pod is running
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l component=kube-apiserver

# Check API server logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n kube-system -l component=kube-apiserver --tail=50

# Check if port 6443 is listening
sudo netstat -tlnp | grep 6443
# or
sudo ss -tlnp | grep 6443
```

### Fix kubeconfig Server Endpoint

If kubeconfig points to wrong address:

```bash
# Check current server endpoint
grep server /root/.kube/config

# Update to correct IP (replace with your master IP)
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://192.168.10.73:6443|' /root/.kube/config
sudo sed -i 's|server: https://localhost:6443|server: https://192.168.10.73:6443|' /root/.kube/config
```

## Common Error: "connection refused" to API server (kubelet can't connect)

This error occurs when kubelet cannot connect to the API server at the configured address. This causes kube-proxy and other system pods to fail.

**Symptoms:**
```
dial tcp 192.168.10.73:6443: connect: connection refused
kube-proxy CrashLoopBackOff
```

**Root Causes:**
1. API server binding to localhost only (not 0.0.0.0)
2. Firewall blocking port 6443
3. API server not running
4. Wrong bind address in API server manifest

### Quick Fix Using Playbook

```bash
cd ansible
ansible-playbook playbooks/fix-api-server-connection.yml -i inventory-devops.yml
```

### Manual Fix

```bash
# SSH into master node
ssh support@192.168.10.73

# Check if API server is listening
sudo netstat -tlnp | grep 6443
# or
sudo ss -tlnp | grep 6443

# Check API server bind address
sudo grep -E '--bind-address|--advertise-address' /etc/kubernetes/manifests/kube-apiserver.yaml

# Fix bind address if it's 127.0.0.1
sudo sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-apiserver.yaml
sudo sed -i 's/--advertise-address=127.0.0.1/--advertise-address=192.168.10.73/' /etc/kubernetes/manifests/kube-apiserver.yaml

# Or add if missing
sudo sed -i '/--authorization-mode/a\    - --bind-address=0.0.0.0\n    - --advertise-address=192.168.10.73' /etc/kubernetes/manifests/kube-apiserver.yaml

# Restart kubelet to pick up changes
sudo systemctl restart kubelet

# Wait for API server to restart (30-60 seconds)
sleep 30

# Check API server health
kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw=/healthz

# Check firewall
sudo ufw status
sudo ufw allow 6443/tcp

# Restart kube-proxy
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n kube-system -l k8s-app=kube-proxy
```

### Verify Fix

```bash
# Check API server is listening
sudo ss -tlnp | grep 6443
# Should show: LISTEN 0 4096 0.0.0.0:6443

# Check API server is accessible
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info

# Check kube-proxy status
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l k8s-app=kube-proxy

# Check kubelet can connect
sudo journalctl -u kubelet -n 50 | grep -i "connection\|refused"
```

## Common Error: Control Plane Components CrashLoopBackOff (kube-scheduler, kube-controller-manager)

Control plane components (kube-scheduler, kube-controller-manager) failing usually indicates API server connectivity issues.

**Symptoms:**
```
kube-scheduler CrashLoopBackOff
kube-controller-manager CrashLoopBackOff
```

**Root Causes:**
1. API server not accessible (connection refused)
2. API server bind address incorrect
3. Scheduler/Controller kubeconfig pointing to wrong address
4. API server not ready when components start

### Quick Fix Using Playbook

```bash
cd ansible
ansible-playbook playbooks/fix-control-plane-components.yml -i inventory-devops.yml
```

### Manual Fix

```bash
# SSH into master node
ssh support@192.168.10.73

# Check all control plane pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l tier=control-plane

# Check scheduler logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n kube-system -l component=kube-scheduler --tail=50

# Check controller manager logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n kube-system -l component=kube-controller-manager --tail=50

# Verify API server is accessible
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info

# If API server is not accessible, fix it first (see "connection refused" section)

# Restart kubelet to reload static pods
sudo systemctl restart kubelet

# Wait for pods to restart (30-60 seconds)
sleep 30

# Check status again
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l tier=control-plane
```

### Check Scheduler/Controller Kubeconfigs

```bash
# Check scheduler kubeconfig
sudo cat /etc/kubernetes/scheduler.conf | grep server

# Check controller manager kubeconfig
sudo cat /etc/kubernetes/controller-manager.conf | grep server

# If they point to localhost, they should work (static pods use localhost)
# But verify API server is accessible on localhost
curl -k https://127.0.0.1:6443/healthz
```

## Common Error: "x509: certificate signed by unknown authority"

This error occurs when kubectl cannot verify the Kubernetes API server certificate.

**Symptoms:**
```
Unable to connect to the server: tls: failed to verify certificate: 
x509: certificate signed by unknown authority
```

**Root Causes:**
1. kubeconfig server endpoint doesn't match certificate
2. Certificate authority data missing or corrupted
3. kubeconfig copied incorrectly
4. Server address mismatch

### Quick Fix Using Playbook

```bash
cd ansible
ansible-playbook playbooks/fix-kubeconfig-certificate.yml -i inventory-devops.yml
```

### Manual Fix

```bash
# SSH into master node
ssh support@192.168.10.73

# Option 1: Use admin.conf directly (always works on master)
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info

# Option 2: Copy fresh admin.conf
sudo cp /etc/kubernetes/admin.conf /root/.kube/config

# Option 3: Update server endpoint in kubeconfig
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://192.168.10.73:6443|' /root/.kube/config
sudo sed -i 's|server: https://localhost:6443|server: https://192.168.10.73:6443|' /root/.kube/config

# Verify
kubectl --kubeconfig=/root/.kube/config cluster-info
```

### Check Certificate

```bash
# Check certificate in kubeconfig
kubectl --kubeconfig=/root/.kube/config config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d | openssl x509 -text -noout

# Check server endpoint
kubectl --kubeconfig=/root/.kube/config config view -o jsonpath='{.clusters[0].cluster.server}'
```

### Regenerate kubeconfig

If the above doesn't work:

```bash
# Backup old config
sudo cp /root/.kube/config /root/.kube/config.backup

# Copy fresh admin.conf
sudo cp /etc/kubernetes/admin.conf /root/.kube/config

# Update server endpoint
MASTER_IP=192.168.10.73
sudo sed -i "s|server: https://127.0.0.1:6443|server: https://$MASTER_IP:6443|" /root/.kube/config
sudo sed -i "s|server: https://localhost:6443|server: https://$MASTER_IP:6443|" /root/.kube/config

# Verify
kubectl --kubeconfig=/root/.kube/config cluster-info
```

## Common Error: kube-proxy CrashLoopBackOff

This error occurs when kube-proxy cannot start, usually because:

1. **CNI plugin not installed** - kube-proxy needs the CNI network plugin to be ready
2. **Network configuration issues** - IP forwarding or bridge networking not configured
3. **Image pull failures** - kube-proxy image cannot be pulled

### Quick Fix Using Playbook

```bash
cd ansible
ansible-playbook playbooks/fix-kube-proxy.yml -i inventory-devops.yml
```

### Manual Fix

```bash
# SSH into master node
ssh support@192.168.10.73

# Check if CNI is installed
kubectl get pods -n kube-flannel
# or for Calico:
kubectl get pods -n kube-system -l k8s-app=calico-node

# If CNI is not installed, install Flannel:
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for CNI to be ready
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s

# Delete and restart kube-proxy pods
kubectl delete pod -n kube-system -l k8s-app=kube-proxy

# Wait for kube-proxy to restart
kubectl wait --for=condition=ready pod -l k8s-app=kube-proxy -n kube-system --timeout=180s

# Check status
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

### Check kube-proxy Logs

```bash
# Get kube-proxy pod name
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Check logs
kubectl logs -n kube-system <kube-proxy-pod-name>

# Check all kube-proxy logs
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50
```

### Verify Network Configuration

```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should output: net.ipv4.ip_forward = 1

# Check bridge networking
lsmod | grep br_netfilter
# Should show br_netfilter module loaded

# Check sysctl settings
cat /etc/sysctl.d/99-kubernetes.conf
```

### If kube-proxy Still Fails

1. **Check node status:**
   ```bash
   kubectl get nodes
   kubectl describe node <node-name>
   ```

2. **Check kubelet logs:**
   ```bash
   sudo journalctl -u kubelet -n 100
   ```

3. **Verify CNI is working:**
   ```bash
   # Check CNI pods are running
   kubectl get pods -n kube-flannel
   kubectl get pods -n kube-system -l k8s-app=calico-node
   
   # Check CNI logs
   kubectl logs -n kube-flannel -l app=flannel
   ```

4. **Reinstall CNI if needed:**
   ```bash
   # Remove existing CNI
   kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   
   # Reinstall
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

