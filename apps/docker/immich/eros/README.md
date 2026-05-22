# Immich — Eros

**URL:** https://eros.hughboi.cc
**Docs:** https://immich.app/docs/

Second Immich instance for a separate photo library. Runs independently from the `home` instance with its own database, storage, and ML container.

## Stack

Same architecture as `immich/home` — see [../home/README.md](../home/README.md) for full service descriptions.

| Container | Role |
|---|---|
| `immich_server-eros` | Main API + web UI |
| `immich_machine_learning-eros` | Face recognition, CLIP, smart albums |
| `immich_redis-eros` | Job queue |
| `immich_postgres-eros` | Database |

## Key Differences from Home Instance

- **GPU access:** Uses `/dev/dri` device pass-through with `group_add: "993"` (render group) for hardware-accelerated transcoding at the server level. The ML container uses OpenVINO via `hwaccel.ml.yml`.
- **Upload storage:** Controlled by `${UPLOAD_LOCATION}` in `.env` (not hardcoded like the home instance)
- **External media:** `/mnt/truenas/eros:/mnt/media/eros:ro`
- **ML cache:** Stored at `/mnt/truenas/eros/cache` (on TrueNAS NFS, not a named volume)
- **Network:** `eros` (internal), `proxy` (Traefik)

## Volumes

| Mount | Purpose |
|---|---|
| `${UPLOAD_LOCATION}` | Uploaded photos and videos |
| `/mnt/truenas/eros:/mnt/media/eros:ro` | External NFS media library |
| `/mnt/truenas/eros/cache` | ML model cache (on NFS) |
| `immich-postgres-eros` | PostgreSQL data |

## Environment Variables (`.env`)

Same as the home instance plus:

| Variable | Purpose |
|---|---|
| `UPLOAD_LOCATION` | Host path for uploaded photos |
| `IMMICH_VERSION` | Image tag — defaults to `v2.7.5` if unset |

## Render Group

The server container adds group `993` via `group_add` — this is the `render` group on the host, which grants access to `/dev/dri` for Intel Quick Sync / VA-API transcoding. Verify the correct GID with:
```sh
stat -c "%g" /dev/dri/renderD128
```
Update the `993` value in compose if the GID differs on the host.

## First Run

Same as the home instance — see [../home/README.md](../home/README.md#first-run).

## Upgrade Notes

Same process as the home instance. Both instances should be upgraded together to keep them on the same Immich version. Mixing versions between eros and home is fine (they're independent stacks) but keeping them in sync makes maintenance simpler.

## Troubleshooting

Same as the home instance — see [../home/README.md](../home/README.md#troubleshooting).

**GPU transcoding not working (eros-specific):**
- Verify `/dev/dri` is accessible: `ls -la /dev/dri/`
- Check that the container's group_add GID matches the render group: `stat -c "%g" /dev/dri/renderD128`
- Check `docker logs immich_server-eros` for VA-API initialization messages
