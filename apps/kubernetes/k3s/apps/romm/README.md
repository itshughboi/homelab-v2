# RomM

Self-hosted game ROM manager and metadata scraper.

## Overview

| | |
|---|---|
| **Image** | `rommapp/romm:latest` |
| **Domain** | `romm.hughboi.vip` |
| **Port** | 8080 |
| **Containers** | romm + MariaDB |
| **Storage** | 5Gi (mysql) + 10Gi (resources/covers) + 100Gi (game library) + 10Gi (assets/saves) + 1Gi (redis cache) |

## Before You Apply

Generate API keys and fill [secret.yaml](secret.yaml):
- `ROMM_AUTH_SECRET_KEY`: `openssl rand -hex 32`
- `IGDB_CLIENT_ID` / `IGDB_CLIENT_SECRET`: https://api-docs.igdb.com/#account-creation
- `STEAMGRIDDB_API_KEY`: https://www.steamgriddb.com/api/v2
- `RETROACHIEVEMENTS_API_KEY`: https://retroachievements.org

```bash
kubectl create secret generic romm-env -n romm \
  --from-literal=MYSQL_ROOT_PASSWORD=<root-pw> \
  --from-literal=DB_PASSWD=<db-pw> \
  --from-literal=ROMM_AUTH_SECRET_KEY=$(openssl rand -hex 32) \
  --from-literal=IGDB_CLIENT_ID=<id> \
  --from-literal=IGDB_CLIENT_SECRET=<secret> \
  --from-literal=STEAMGRIDDB_API_KEY=<key> \
  --from-literal=RETROACHIEVEMENTS_API_KEY=<key>
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f mariadb.yaml
kubectl rollout status deployment/romm-mariadb -n romm
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Notes

- `romm-library` is a 100Gi Longhorn PVC by default. If your game library is on TrueNAS, replace with an NFS PV (see `file-browser/storage.yaml` for the pattern).
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- RomM includes a built-in Redis cache in the container image — the `romm-redis` PVC backs the `/redis-data` mount inside the app container.
- Add `romm` to the Reflector annotation on the TLS certificate.
