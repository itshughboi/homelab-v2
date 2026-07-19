# ezBookkeeping

Lightweight personal bookkeeping application backed by MySQL.

## Overview

| | |
|---|---|
| **Image** | `mayswind/ezbookkeeping:latest` |
| **Domain** | `bookkeeping.hughboi.cc` |
| **Port** | 8080 |
| **Containers** | ezbookkeeping + MySQL 8.0 |
| **Storage** | 5Gi PVC (MySQL) + 2Gi PVC (app storage/logs) |

## Before You Apply

```bash
kubectl create secret generic ezbookkeeping-env -n ezbookkeeping \
  --from-literal=EBK_DATABASE_PASSWD=<password> \
  --from-literal=MYSQL_ROOT_PASSWORD=<root-password> \
  --from-literal=EBK_SECURITY_SECRET_KEY=$(openssl rand -hex 32)
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f mysql.yaml
kubectl rollout status deployment/ezbookkeeping-mysql -n ezbookkeeping
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVCs.
- The init container waits for MySQL before starting the app.
- Add `ezbookkeeping` to the Reflector annotation on the TLS certificate.
