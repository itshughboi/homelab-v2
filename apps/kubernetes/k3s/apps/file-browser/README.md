# File Browser

Web-based file manager for browsing TrueNAS NFS shares.

## Overview

| | |
|---|---|
| **Image** | `hurlenko/filebrowser:latest` |
| **Domain** | `files.hughboi.vip` |
| **Port** | 8080 |
| **Storage** | TrueNAS NFS PV (`/data`) + 1Gi Longhorn PVC (`/config` — filebrowser.db) |

## Before You Apply

Fill in `TRUENAS_IP` and the NFS path in [storage.yaml](storage.yaml):

```yaml
nfs:
  server: 10.10.10.50         # Your TrueNAS IP
  path: /mnt/tank/data        # The NFS export you want to browse
```

Confirm the NFS export is accessible from cluster nodes:
```bash
showmount -e 10.10.10.50
```

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f storage.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

File Browser's database (bookmarks, users, settings) lives in `/config/filebrowser.db`:
```bash
kubectl scale deployment file-browser -n file-browser --replicas=0
kubectl run copy --image=alpine -n file-browser --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/filebrowser/db/filebrowser.db file-browser/copy:/config/
kubectl delete pod copy -n file-browser
kubectl scale deployment file-browser -n file-browser --replicas=1
```

## Notes

- The NFS PV uses `ReadWriteMany` — multiple pods can read the share simultaneously, but File Browser only runs one replica.
- The app runs as `uid=1000` — ensure the NFS export allows access from this UID (or configure `no_root_squash` / `anonuid=1000`).
- `strategy: Recreate` required for the Longhorn PVC (ReadWriteOnce).
- Add `file-browser` to the Reflector annotation on the TLS certificate.
