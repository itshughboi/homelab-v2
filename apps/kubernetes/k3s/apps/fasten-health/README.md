# Fasten Health

Self-hosted personal health records aggregator. Connects to healthcare providers via SMART on FHIR.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/fastenhealth/fasten-onprem:main` |
| **Domain** | `fastenhealth.hughboi.cc` |
| **Port** | 8080 |
| **Storage** | 5Gi Longhorn PVC (`/opt/fasten/db`) + 2Gi Longhorn PVC (`/opt/fasten/cache`) |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment fasten-health -n fasten-health --replicas=0
kubectl run copy --image=alpine -n fasten-health --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/fasten-health/db/. fasten-health/copy:/opt/fasten/db/
kubectl delete pod copy -n fasten-health
kubectl scale deployment fasten-health -n fasten-health --replicas=1
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVCs.
- The `main` tag follows the development branch — pin to a release tag if you want stability.
- Add `fasten-health` to the Reflector annotation on the TLS certificate.
- The Docker compose also mounted a `config.yaml` — if you have custom config, add it as a ConfigMap and mount at `/opt/fasten/config/config.yaml`.
