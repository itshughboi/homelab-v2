# Change Detection

Website change monitoring. Uses a Playwright/Chrome sidecar for JavaScript-heavy pages.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/dgtlmoon/changedetection.io:latest` |
| **Domain** | `change.hughboi.vip` |
| **Port** | 5000 |
| **Chrome** | `browserless/chrome:latest` (sidecar in same pod) |
| **Storage** | 5Gi Longhorn PVC (`/datastore`) |

## Design

The app and Chrome run in the **same pod** (two containers sharing localhost). Change Detection connects to Chrome via `ws://localhost:3000`. This avoids cross-pod networking and keeps latency near zero.

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
kubectl scale deployment change-detection -n change-detection --replicas=0
kubectl run copy --image=alpine -n change-detection --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/change-detection/. change-detection/copy:/datastore/
kubectl delete pod copy -n change-detection
kubectl scale deployment change-detection -n change-detection --replicas=1
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- Chrome gets 1Gi memory limit — lower if cluster is memory-constrained, but below 512Mi it becomes unstable with complex pages.
- Add `change-detection` to the Reflector annotation on the TLS certificate.
