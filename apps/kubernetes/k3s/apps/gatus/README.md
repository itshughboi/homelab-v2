# Gatus

Uptime/health monitoring dashboard with alerting.

## Overview

| | |
|---|---|
| **Image** | `twinproduction/gatus:latest` |
| **Domain** | `gatus.hughboi.cc` |
| **Port** | 8080 |
| **Storage** | 2Gi Longhorn PVC (PostgreSQL data — status history) |

## Files

| File | Purpose |
|------|---------|
| [configmap.yaml](configmap.yaml) | `config.yaml` — endpoints, alerting rules |
| [secret.yaml](secret.yaml) | Postgres credentials + ntfy URL |
| [postgres.yaml](postgres.yaml) | PostgreSQL Deployment + Service |
| [deployment.yaml](deployment.yaml) | Gatus Deployment (waits for postgres) |
| [service.yaml](service.yaml) | ClusterIP Service |
| [ingressroute.yaml](ingressroute.yaml) | Traefik IngressRoute |

## Before You Apply

1. Fill in [secret.yaml](secret.yaml) — set `POSTGRES_PASSWORD` and `NTFY_URL`.
2. Edit [configmap.yaml](configmap.yaml) — add/remove endpoints and update alert topics.

```bash
kubectl create secret generic gatus-env -n gatus \
  --from-literal=POSTGRES_USER=gatus \
  --from-literal=POSTGRES_PASSWORD=<password> \
  --from-literal=POSTGRES_DB=gatus \
  --from-literal=NTFY_URL=https://ntfy.hughboi.cc
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f postgres.yaml
kubectl rollout status deployment/gatus-postgres -n gatus
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Updating Endpoints

Edit [configmap.yaml](configmap.yaml), then:
```bash
kubectl apply -f configmap.yaml
kubectl rollout restart deployment/gatus -n gatus
```

## Notes

- Status history is stored in PostgreSQL — the Docker setup connected to an external Postgres. The k8s setup includes a dedicated Postgres pod.
- The init container waits for Postgres before starting Gatus.
- Gatus supports many alert providers beyond ntfy — see [Gatus docs](https://github.com/TwiN/gatus#alerting) for Discord, PagerDuty, etc.
- Add `gatus` to the Reflector annotation on the TLS certificate.
