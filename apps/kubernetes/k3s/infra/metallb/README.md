# MetalLB

Layer 2 LoadBalancer for k3s. Assigns real LAN IPs to `type: LoadBalancer` services so external clients (browsers, APs, devices) can reach them directly without a cloud load balancer.

## Overview

| | |
|---|---|
| **Mode** | L2 (ARP) |
| **IP Pool** | `10.10.30.60 – 10.10.30.99` |
| **Notable allocations** | `10.10.30.65` – AdGuard DNS, `10.10.30.75` – Traefik |

## How It Works

MetalLB watches for Services with `type: LoadBalancer`. When one is created, it picks an IP from the pool, updates the service's `status.loadBalancer.ingress`, and sends gratuitous ARPs so LAN clients can reach it. No BGP, no cloud — pure ARP announcement.

`externalTrafficPolicy: Local` is set on Traefik and AdGuard so the source IP is preserved (needed for CrowdSec to see real client IPs, not cluster-internal hops).

## Files

| File | Purpose |
|------|---------|
| [ip-address-pool.yaml](ip-address-pool.yaml) | Defines the IP range MetalLB can hand out |
| [l2-advertisement.yaml](l2-advertisement.yaml) | Ties the pool to L2 advertisement mode |

## Deploy

MetalLB itself is installed via Helm (or the official manifest). Once the controller is running, apply the pool configuration:

```bash
# Install MetalLB (if not already done)
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace

# Wait for MetalLB to be ready
kubectl rollout status deployment/metallb-controller -n metallb-system

# Apply pool config
kubectl apply -f ip-address-pool.yaml
kubectl apply -f l2-advertisement.yaml
```

Fill in `$lbrange` in [ip-address-pool.yaml](ip-address-pool.yaml) with the actual range before applying:

```yaml
addresses:
  - 10.10.30.60-10.10.30.99
```

## Verify

```bash
# Check a service got an external IP
kubectl get svc -A | grep LoadBalancer

# Check MetalLB assigned it
kubectl describe svc <service-name> -n <namespace> | grep "LoadBalancer Ingress"
```

## Notes

- kube-vip handles the **control-plane VIP** (10.10.30.30) only. MetalLB handles all **service** LoadBalancer IPs.
- Do not overlap the MetalLB pool with DHCP ranges on your router.
- If a service is stuck in `<pending>` for `EXTERNAL-IP`, check that the pool has free addresses: `kubectl get ipaddresspool -n metallb-system`.
