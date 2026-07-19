# FreshRSS

Self-hosted RSS feed aggregator.

## Overview

| | |
|---|---|
| **Image** | `lscr.io/linuxserver/freshrss:latest` |
| **Domain** | `freshrss.hughboi.cc` |
| **Port** | 80 |
| **Storage** | 2Gi Longhorn PVC (`/config` — SQLite db, feeds, themes, extensions) |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

The linuxserver image stores everything in `/config`. Copy it from the Docker host:

```bash
kubectl scale deployment freshrss -n freshrss --replicas=0
kubectl run copy --image=alpine -n freshrss --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/rss/. freshrss/copy:/config/
kubectl delete pod copy -n freshrss
kubectl scale deployment freshrss -n freshrss --replicas=1
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- The linuxserver image handles PUID/PGID for correct file ownership.
- Add `freshrss` to the Reflector annotation on the TLS certificate.
- FreshRSS supports PostgreSQL and MySQL if you want to externalize the database — the linuxserver image defaults to SQLite which is fine for a single user.
