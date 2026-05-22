# AdGuard Home

Network-wide DNS ad blocking and filtering for the k3s cluster network.

## Overview

| | |
|---|---|
| **Image** | `adguard/adguardhome:v0.107.41` |
| **External IP** | `10.10.30.65` (MetalLB LoadBalancer) |
| **DNS Ports** | 53/UDP, 53/TCP |
| **Admin UI** | Port 3000 (via LoadBalancer IP, not Traefik) |
| **Storage** | Longhorn PVC (`/opt/adguardhome/work` — query logs, stats) |
| **Config** | ConfigMap (`/opt/adguardhome/conf`) |

## Files

| File | Purpose |
|------|---------|
| [adguard-namespace.yml](adguard-namespace.yml) | `adguard` namespace |
| [adguard-secret.yml](adguard-secret.yml) | Credentials (fill before applying) |
| [adguard-pvc.yml](adguard-pvc.yml) | Longhorn PVC for work directory |
| [adguard-configmap.yml](adguard-configmap.yml) | `AdGuardHome.yaml` config mounted at `/opt/adguardhome/conf` |
| [adguard-deployment.yml](adguard-deployment.yml) | Single-replica Deployment |
| [adguard-service.yml](adguard-service.yml) | LoadBalancer Service (DNS + admin UI) |

## Deploy

```bash
kubectl apply -f adguard-namespace.yml
kubectl apply -f adguard-secret.yml
kubectl apply -f adguard-pvc.yml
kubectl apply -f adguard-configmap.yml
kubectl apply -f adguard-deployment.yml
kubectl apply -f adguard-service.yml
```

After deploy, point your router/DHCP server's DNS to `10.10.30.65`. The admin UI is at `http://10.10.30.65:3000`.

## Configuration

DNS settings and filter lists live in [adguard-configmap.yml](adguard-configmap.yml). Editing the ConfigMap and restarting the pod applies the new config:

```bash
kubectl apply -f adguard-configmap.yml
kubectl rollout restart deployment/adguard-deployment -n adguard
```

Note that AdGuard Home also writes runtime state (query stats, session data) into the `work` PVC — this survives restarts. The ConfigMap only controls the initial/static config.

## Prometheus Scraping

The Service has `prometheus.io/scrape: "true"` and `prometheus.io/port: "3000"` annotations. If using the kube-prometheus-stack with annotation-based discovery, metrics will be scraped automatically. AdGuard's Prometheus endpoint is at `:3000/metrics` (enabled in the AdGuard config).

## Notes

- `strategy: Recreate` is required since the PVC is `ReadWriteOnce`.
- The container runs as `uid=1000` (`runAsNonRoot: true`) with a read-only root filesystem — writes only go to the two mounted volumes.
- `externalTrafficPolicy: Local` on the Service preserves client IPs in query logs.
- No Traefik IngressRoute is set up for the admin UI — access it directly via the LoadBalancer IP. Adding one is straightforward if desired.
- Update the image tag in [adguard-deployment.yml](adguard-deployment.yml) to upgrade. Check [AdGuard Home releases](https://github.com/AdguardTeam/AdGuardHome/releases) for the latest stable tag.
