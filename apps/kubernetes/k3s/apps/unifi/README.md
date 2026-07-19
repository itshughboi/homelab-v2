# UniFi Network Controller

> **TEST ENVIRONMENT ONLY.**
> Deploying this in production requires re-adopting every AP, switch, and gateway to the new controller IP. That means brief network interruptions. Use this to learn the setup before committing to a cutover.

## Overview

| | |
|---|---|
| **Domain** | `unifi.hughboi.cc` (web UI via Traefik) |
| **UI Port** | 8443 (HTTPS, proxied by Traefik with `insecureSkipVerify=true`) |
| **Containers** | controller + mongodb (latest, fresh) + unifi-poller |

Mongo is intentionally set to `latest` (fresh start). Since you opted for a clean slate, there's no data migration needed.

The `logs` sidecar from Docker (alpine running `tail -F`) is dropped — Alloy collects pod logs automatically.

## Ports

| Service | Type | Ports | Purpose |
|---------|------|-------|---------|
| `unifi-controller` | ClusterIP | 8443, 8080 | Used by Traefik IngressRoute + internal |
| `unifi-controller-lb` | LoadBalancer | 3478/udp, 10001/udp, 8080, 6789, 8880, 8843 | APs, STUN, speed test, portals |

## Before You Apply

### 1. Enable the sysctl on k3s nodes

The controller needs `net.ipv4.ip_unprivileged_port_start=0` to bind ports as the `unifi` user. Add to your k3s server config on each node:

```yaml
# /etc/rancher/k3s/config.yaml
kubelet-arg:
  - "allowed-unsafe-sysctls=net.ipv4.ip_unprivileged_port_start"
```

Restart k3s after: `systemctl restart k3s`

### 2. Fill in the poller secret

```bash
kubectl create secret generic unifi-poller-env -n unifi \
  --from-literal=UP_UNIFI_CONTROLLER_0_URL=https://unifi-controller:8443 \
  --from-literal=UP_UNIFI_DEFAULT_USER=unifi-poller \
  --from-literal=UP_UNIFI_DEFAULT_PASS=<password> \
  --from-literal=UP_UNIFI_CONTROLLER_0_PASS=<password> \
  --from-literal=UP_UNIFI_CONTROLLER_0_INSECURE=true \
  --from-literal=UP_POLLER_DEBUG=false
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f storage.yaml
kubectl apply -f mongodb.yaml
kubectl rollout status deployment/mongo -n unifi
kubectl apply -f controller.yaml
kubectl apply -f unifi-poller.yaml
kubectl apply -f ingressroute.yaml
```

## After Deploy

Get the LoadBalancer IP assigned to `unifi-controller-lb`:

```bash
kubectl get svc unifi-controller-lb -n unifi
```

This is the IP your APs and switches need to reach. If testing against live devices, update the inform URL in the UniFi controller: `Settings → System → Advanced → Inform Host`.

## Prometheus Scraping

If you're using the k8s Prometheus stack, add a scrape target for `unifi-poller` in the kube-prometheus-stack values:

```yaml
additionalScrapeConfigs:
  - job_name: unifipoller
    scrape_interval: 30s
    static_configs:
      - targets: ['unifi-poller.unifi.svc.cluster.local:9130']
```

If you do this, remove `10.10.10.10:9130` from the Docker Prometheus scrape config to avoid duplicate metrics.
