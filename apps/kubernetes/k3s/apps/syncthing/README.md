# Syncthing

Continuous file sync between devices.

## Overview

| | |
|---|---|
| **Image** | `syncthing/syncthing:2.0.8` |
| **Domain** | `syncthing.hughboi.vip` |
| **UI Port** | 8384 (via Traefik) |
| **Sync Ports** | 22000/tcp, 22000/udp (QUIC), 21027/udp (local discovery) |
| **Storage** | 50Gi Longhorn PVC (`/var/syncthing` — config + default sync folder) |

## Services

Two Services are deployed:

| Service | Type | Purpose |
|---------|------|---------|
| `syncthing-ui` | ClusterIP | Web UI consumed by Traefik IngressRoute |
| `syncthing-sync` | LoadBalancer | Sync ports — remote devices connect here directly |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f services.yaml
kubectl apply -f ingressroute.yaml
```

## After Deploy

Get the LoadBalancer IP MetalLB assigned to the sync service:

```bash
kubectl get svc syncthing-sync -n syncthing
```

Update all remote Syncthing devices to use this IP for the connection address (`syncthing-sync` EXTERNAL-IP, port 22000).

If migrating from Docker, the Syncthing device ID stays the same as long as you copy the existing config:

```bash
kubectl run copy --image=alpine -n syncthing --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/syncthing/. syncthing/copy:/var/syncthing/
kubectl delete pod copy -n syncthing
```

## Notes

- `strategy: Recreate` required for the `ReadWriteOnce` PVC.
- If you sync folders outside `/var/syncthing` (e.g. NAS paths), add extra NFS PersistentVolumes to [storage.yaml](pvc.yaml) and mount them in the Deployment.
- Local discovery (21027/udp) only works within the same broadcast domain. If your Syncthing peers are on a different subnet, they'll need the explicit LoadBalancer IP configured.
