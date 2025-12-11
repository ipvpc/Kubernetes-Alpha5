# Fixing Traefik Permission Denied Error

## Problem
Traefik can't bind to port 80/443: `listen tcp :80: bind: permission denied`

## Solution 1: Security Context (Current Fix)

The configuration now includes proper security context under `deployment`:
- `NET_BIND_SERVICE` capability
- Running as root (UID 0)
- Proper pod security context

## Solution 2: If Security Context Doesn't Work

If the security context approach still fails, you can use `hostNetwork: true`:

```yaml
deployment:
  hostNetwork: true
```

**Note:** This reduces network isolation but allows binding to privileged ports.

## Solution 3: Manual Fix (If Helm Chart Structure is Different)

If the Helm chart structure is different, you can manually patch the deployment:

```bash
# Get the deployment name
kubectl get deployment -n traefik

# Patch the deployment to add security context
kubectl patch deployment traefik -n traefik --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/securityContext",
    "value": {
      "fsGroup": 0
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/securityContext",
    "value": {
      "capabilities": {
        "drop": ["ALL"],
        "add": ["NET_BIND_SERVICE"]
      },
      "runAsUser": 0,
      "runAsGroup": 0,
      "runAsNonRoot": false
    }
  }
]'
```

## Solution 4: Use Non-Privileged Ports (Alternative)

If you can't use privileged ports, configure Traefik to use higher ports:

```yaml
additionalArguments:
  - "--entrypoints.web.address=:8080"
  - "--entrypoints.websecure.address=:8443"
```

Then configure your LoadBalancer/Service to map 80→8080 and 443→8443.

## Verification

After applying the fix:

```bash
# Check Traefik pods
kubectl get pods -n traefik

# Check logs (should not show permission denied)
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Verify Traefik is listening on ports
kubectl exec -n traefik <pod-name> -- netstat -tlnp | grep -E ':(80|443)'
```

## Current Configuration

The Terraform configuration now includes:
- Security context with `NET_BIND_SERVICE` capability
- Running as root (UID 0) 
- Proper pod security context (fsGroup 0)

This should resolve the permission denied error.

