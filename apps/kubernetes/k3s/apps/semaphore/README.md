# Semaphore

Web UI for running Ansible playbooks. Replaces manual `ansible-playbook` runs with a browser interface, job history, and RBAC.

## Overview

| | |
|---|---|
| **Image** | `semaphoreui/semaphore:latest` |
| **Domain** | `semaphore.hughboi.vip` |
| **Port** | 3000 |
| **Containers** | semaphore + MySQL 8.4 |
| **Storage** | 5Gi PVC (MySQL) + 1Gi PVC (Semaphore config) |

## Before You Apply

```bash
kubectl create secret generic semaphore-env -n semaphore \
  --from-literal=MYSQL_DATABASE=semaphore \
  --from-literal=MYSQL_USER=semaphore \
  --from-literal=MYSQL_PASSWORD=<db-password> \
  --from-literal=SEMAPHORE_DB_USER=semaphore \
  --from-literal=SEMAPHORE_DB_PASS=<db-password> \
  --from-literal=SEMAPHORE_DB_HOST=semaphore-mysql \
  --from-literal=SEMAPHORE_DB_PORT=3306 \
  --from-literal=SEMAPHORE_DB_DIALECT=mysql \
  --from-literal=SEMAPHORE_DB=semaphore \
  --from-literal=SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/ \
  --from-literal=SEMAPHORE_ADMIN_PASSWORD=<admin-password> \
  --from-literal=SEMAPHORE_ADMIN_NAME=admin \
  --from-literal=SEMAPHORE_ADMIN_EMAIL=admin@hughboi.vip \
  --from-literal=SEMAPHORE_ADMIN=admin \
  --from-literal=SEMAPHORE_ACCESS_KEY_ENCRYPTION=$(openssl rand -base64 32) \
  --from-literal=ANSIBLE_HOST_KEY_CHECKING=false
```

## SSH Keys for Ansible

Semaphore needs SSH keys to connect to managed hosts. Store them as a Secret:

```bash
kubectl create secret generic semaphore-ssh-keys -n semaphore \
  --from-file=id_ed25519=/home/hughboi/.ssh/id_ed25519 \
  --from-file=id_ed25519.pub=/home/hughboi/.ssh/id_ed25519.pub
```

In Semaphore UI: `Key Store → New Key → SSH Key` — paste the private key content.

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f mysql.yaml
kubectl rollout status deployment/semaphore-mysql -n semaphore
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Setting Up Inventory

In Semaphore UI, point the inventory at your `ansible/inventories/hosts.ini` by either:
1. Pasting it directly as a "Static" inventory
2. Connecting Semaphore to Gitea and pulling from the repo

## Notes

- `SEMAPHORE_ACCESS_KEY_ENCRYPTION` must be stable — rotating it invalidates all stored SSH keys and passwords in Semaphore's database.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- The Docker compose mounted `/inventory` and `/authorized-keys` from host paths. In k8s these are provided via the Secret volume.
- Add `semaphore` to the Reflector annotation on the TLS certificate.
