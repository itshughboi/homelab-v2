# Vaultwarden

Bitwarden-compatible self-hosted password manager.

## Overview

| | |
|---|---|
| **Image** | `vaultwarden/server:1.35.7` |
| **Domain** | `vaultwarden.hughboi.cc` |
| **Port** | 80 |
| **Storage** | 1Gi Longhorn PVC (`/data` — SQLite db + attachments) |

## Before You Apply

1. Fill in [secret.yaml](secret.yaml) with real values, or create the secret imperatively:
   ```bash
   kubectl create secret generic vaultwarden-env -n vaultwarden \
     --from-literal=DOMAIN=https://vaultwarden.hughboi.cc \
     --from-literal=ADMIN_TOKEN=$(openssl rand -base64 48) \
     --from-literal=SMTP_HOST=mailrise.hughboi.cc \
     --from-literal=SMTP_PORT=8025 \
     --from-literal=SMTP_SECURITY=off \
     --from-literal=SMTP_FROM=vaultwarden@hughboi.cc \
     --from-literal=SMTP_FROM_NAME=Vaultwarden \
     --from-literal=SMTP_USERNAME="" \
     --from-literal=SMTP_PASSWORD=""
   ```

2. Ensure `hughboi-tls` is reflected into the `vaultwarden` namespace (Reflector annotation is on the cert — give it ~30s after namespace creation).

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml   # after filling in values
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

If you have existing data from the Docker stack:

```bash
# Scale down the k8s deployment first
kubectl scale deployment vaultwarden -n vaultwarden --replicas=0

# Copy data from Docker host into the PVC (via a temp pod)
kubectl run copy --image=alpine -n vaultwarden --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/vaultwarden/data/. vaultwarden/copy:/data/

# Scale back up
kubectl delete pod copy -n vaultwarden
kubectl scale deployment vaultwarden -n vaultwarden --replicas=1
```

## Notes

- `strategy: Recreate` is required — the `ReadWriteOnce` PVC can only be mounted by one pod at a time.
- The Ansible backup playbooks in `ansible/playbooks/vaultwarden/` target the Docker host. After cutover, update them to use `kubectl exec` to export the SQLite database from the PVC instead.
- Admin panel: `https://vaultwarden.hughboi.cc/admin`
