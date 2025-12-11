# Network Isolation and Service Exposure Guide

This guide explains how to isolate pods from your network while still allowing external access to services.

## Overview

- **Pod Isolation**: Pods are isolated by default using Calico Network Policies
- **Service Exposure**: Services can be exposed via NodePort, LoadBalancer, or Ingress
- **Network Policies**: Fine-grained control over pod-to-pod communication

## Quick Start

### 1. Setup Network Isolation

```bash
cd ansible
ansible-playbook playbooks/setup-network-isolation.yml -i inventory-devops.yml
```

This will:
- Create default deny-all network policy (isolates all pods)
- Allow DNS resolution
- Allow kube-system communication
- Create example network policy templates

### 2. Setup Ingress Controller (Optional but Recommended)

```bash
# For Traefik
ansible-playbook playbooks/setup-ingress.yml -i inventory-devops.yml -e ingress_controller=traefik

# For Nginx
ansible-playbook playbooks/setup-ingress.yml -i inventory-devops.yml -e ingress_controller=nginx
```

### 3. View Service Exposure Examples

```bash
ansible-playbook playbooks/expose-services.yml -i inventory-devops.yml
```

## Network Policies

### Default Policies Created

1. **default-deny-all**: Blocks all ingress and egress traffic by default
2. **allow-dns**: Allows DNS resolution (UDP/TCP port 53)
3. **allow-kube-system**: Allows communication with kube-system namespace

### Creating Custom Network Policies

Example: Allow specific pods to communicate

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-communication
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from specific pods
  - from:
    - podSelector:
        matchLabels:
          app: allowed-client
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow to database
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  # Always allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

Apply:
```bash
kubectl apply -f your-network-policy.yaml
```

## Service Exposure Methods

### 1. NodePort

Exposes service on a high port (30000-32767) on all nodes.

**Create via command:**
```bash
kubectl expose deployment my-app --type=NodePort --port=80 --target-port=8080
```

**Create via manifest:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-nodeport
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30001  # Optional: let Kubernetes assign if omitted
```

**Access:**
```bash
# Get node IP
kubectl get nodes -o wide

# Get NodePort
kubectl get svc my-app-nodeport -o jsonpath='{.spec.ports[0].nodePort}'

# Access
curl http://<node-ip>:<nodeport>
```

### 2. LoadBalancer

Requires a load balancer (cloud provider or MetalLB).

**Create:**
```bash
kubectl expose deployment my-app --type=LoadBalancer --port=80
```

**Access:**
```bash
# Get LoadBalancer IP
kubectl get svc my-app-loadbalancer

# Access
curl http://<loadbalancer-ip>
```

### 3. Ingress

Routes external traffic based on hostname/path. Requires an ingress controller.

**Create Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  annotations:
    # For Traefik
    traefik.ingress.kubernetes.io/rule-type: PathPrefix
spec:
  ingressClassName: nginx  # or traefik
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

**Access:**
```bash
# Add to /etc/hosts (for testing)
<node-ip> app.example.com

# Access
curl http://app.example.com
# Or via ingress NodePort
curl http://<node-ip>:<ingress-nodeport> -H "Host: app.example.com"
```

## Network Policy for Exposed Services

To allow external traffic to reach your service:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-to-service
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Ingress
  ingress:
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: traefik
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  # Allow from NodePort (if using NodePort)
  - from: []
    ports:
    - protocol: TCP
      port: 8080
```

## Complete Example

### 1. Deploy an application

```bash
# Create deployment
kubectl create deployment nginx --image=nginx

# Expose via NodePort
kubectl expose deployment nginx --type=NodePort --port=80
```

### 2. Allow external access via Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-external
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
  - Ingress
  ingress:
  - from: []
    ports:
    - protocol: TCP
      port: 80
```

### 3. Access the service

```bash
# Get NodePort
NODEPORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Access
curl http://$NODE_IP:$NODEPORT
```

## Troubleshooting

### Pods can't communicate

1. **Check network policies:**
   ```bash
   kubectl get networkpolicies -A
   kubectl describe networkpolicy <name>
   ```

2. **Check if default-deny-all is blocking:**
   ```bash
   kubectl get networkpolicy default-deny-all
   ```

3. **Create allow policy for your pods**

### Service not accessible

1. **Check service:**
   ```bash
   kubectl get svc
   kubectl describe svc <service-name>
   ```

2. **Check endpoints:**
   ```bash
   kubectl get endpoints <service-name>
   ```

3. **Check network policy allows ingress:**
   ```bash
   kubectl get networkpolicies
   ```

4. **Check firewall:**
   ```bash
   # On nodes
   sudo ufw status
   sudo iptables -L
   ```

### Ingress not working

1. **Check ingress controller:**
   ```bash
   kubectl get pods -n traefik
   kubectl get pods -n ingress-nginx
   ```

2. **Check ingress:**
   ```bash
   kubectl get ingress
   kubectl describe ingress <name>
   ```

3. **Check ingress controller logs:**
   ```bash
   kubectl logs -n traefik -l app=traefik
   kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
   ```

## Best Practices

1. **Start with default-deny-all**: Isolate everything, then allow what's needed
2. **Use namespaces**: Group related pods in namespaces
3. **Label pods properly**: Use consistent labels for network policies
4. **Test incrementally**: Add network policies one at a time
5. **Use Ingress for HTTP/HTTPS**: Better than NodePort for web services
6. **Document policies**: Keep track of why each policy exists

## Security Considerations

1. **Network policies are additive**: Multiple policies combine (OR logic)
2. **Default deny**: Always start with deny-all
3. **Principle of least privilege**: Only allow necessary traffic
4. **Regular audits**: Review network policies regularly
5. **Monitor traffic**: Use network monitoring tools

## Additional Resources

- [Calico Network Policies](https://docs.tigera.io/calico/latest/network-policy/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

