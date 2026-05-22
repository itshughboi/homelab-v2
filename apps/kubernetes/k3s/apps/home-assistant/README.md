# Home Assistant

Home automation platform with PostgreSQL for recorder storage.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/home-assistant/home-assistant:stable` |
| **Domain** | `ha.hughboi.vip` |
| **Port** | 8123 |
| **Containers** | home-assistant + PostgreSQL |
| **Storage** | 10Gi Longhorn (HA config) + 20Gi Longhorn (postgres) |
| **Network** | `hostNetwork: true` (required for local device discovery) |

## hostNetwork Warning

The pod uses `hostNetwork: true` — the HA container binds directly to the node's NIC. This is required for:
- mDNS / Zeroconf (Chromecast, Apple TV, etc.)
- Zigbee/Z-Wave USB dongle passthrough
- Local device auto-discovery protocols

**Side effect:** HA will be reachable at the node's IP on port 8123, not just via Traefik. The IngressRoute also works as normal.

**If you don't need local device discovery:** Remove `hostNetwork: true` and `dnsPolicy: ClusterFirstWithHostNet` from [deployment.yaml](deployment.yaml) for better isolation.

## PostgreSQL Integration

HA's recorder (history/logbook) is configured to use Postgres via `configuration.yaml`:
```yaml
recorder:
  db_url: postgresql://homeassistant:PASSWORD@home-assistant-postgres:5432/homeassistant
```

Add this after migrating your config, replacing `PASSWORD` with your actual value (or reference a secret via HA's secrets.yaml).

## Before You Apply

```bash
kubectl create secret generic home-assistant-env -n home-assistant \
  --from-literal=POSTGRES_USER=homeassistant \
  --from-literal=POSTGRES_PASSWORD=<password> \
  --from-literal=POSTGRES_DB=homeassistant
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f postgres.yaml
kubectl rollout status deployment/home-assistant-postgres -n home-assistant
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment home-assistant -n home-assistant --replicas=0
kubectl run copy --image=alpine -n home-assistant --restart=Never -- sleep 3600
kubectl cp /config/. home-assistant/copy:/config/
kubectl delete pod copy -n home-assistant
kubectl scale deployment home-assistant -n home-assistant --replicas=1
```

## Notes

- The Docker compose mounted `/config` directly. In k8s this is a Longhorn PVC — same path, different backing.
- USB device passthrough (Zigbee/Z-Wave dongles) requires the pod to schedule on the specific node with the dongle. Use `nodeSelector` to pin it.
- Add `home-assistant` to the Reflector annotation on the TLS certificate.
