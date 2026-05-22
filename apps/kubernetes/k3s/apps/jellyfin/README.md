# Jellyfin

Self-hosted media server for Films, TV Shows, Music, and Concerts.

## Overview

| | |
|---|---|
| **Image** | `jellyfin/jellyfin:latest` |
| **Domain** | `jellyfin.hughboi.vip` |
| **Port** | 8096 |
| **Storage** | 10Gi Longhorn (config) + 20Gi Longhorn (cache) + NFS PVs (media) |

## Media Libraries (NFS)

| Library | NFS Path |
|---------|---------|
| Films | `/mnt/tank/jellyfin/Films` |
| TVShows | `/mnt/tank/jellyfin/TVShows` |
| Music | `/mnt/tank/jellyfin/Music` |
| Concerts | `/mnt/tank/jellyfin/Concerts` |

## Before You Apply

Fill in `TRUENAS_IP` in [storage.yaml](storage.yaml) for all four NFS PersistentVolumes:
```yaml
nfs:
  server: 10.10.10.50   # Your TrueNAS IP
  path: /mnt/tank/jellyfin/Films
```

Confirm NFS exports are accessible from cluster nodes:
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

Copy config from the Docker host:
```bash
kubectl scale deployment jellyfin -n jellyfin --replicas=0
kubectl run copy --image=alpine -n jellyfin --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/jellyfinconfig/. jellyfin/copy:/config/
kubectl delete pod copy -n jellyfin
kubectl scale deployment jellyfin -n jellyfin --replicas=1
```

After startup, Jellyfin may re-scan media libraries — this is expected on first run.

## GPU Transcoding

GPU transcoding is currently disabled (matching Docker config). To enable VAAPI transcoding:

1. Uncomment `securityContext.privileged: true` in [deployment.yaml](deployment.yaml)
2. Add a device mount for the render node:
```yaml
volumes:
  - name: dri
    hostPath:
      path: /dev/dri
volumeMounts:
  - name: dri
    mountPath: /dev/dri
```
3. In Jellyfin UI: `Dashboard → Playback → Transcoding → VAAPI`

## Notes

- Media PVs are `ReadOnlyMany` — Jellyfin reads but never writes to the NFS shares.
- `strategy: Recreate` required for ReadWriteOnce PVCs (config, cache).
- Add `jellyfin` to the Reflector annotation on the TLS certificate.
