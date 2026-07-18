# Immich — Home

**URL:** https://immich.hughboi.cc
**Docs:** https://immich.app/docs/

Self-hosted photo and video library. Replaces Google Photos. Used for the main household photo library with automatic backup from phones.

## Stack

| Container | Image | Role |
|---|---|---|
| `immich_server` | `immich-server` | Main API + web UI |
| `immich_machine_learning` | `immich-machine-learning` | Face recognition, CLIP search, smart albums |
| `immich_redis` | `valkey/valkey` | Job queue and session cache |
| `immich_postgres` | `immich-app/postgres` | Database (PostgreSQL with pgvector for ML search) |

Machine learning uses OpenVINO for Intel GPU acceleration (`SYS_ADMIN` cap + `apparmor=unconfined` required). The server itself also gets GPU access for video transcoding, directly via `/dev/dri` + the host's render group (GID `993`) — same pattern as `apps/docker/immich/eros`, the proven-working reference. Fixed 2026-07-18: this was previously broken (`extends: hwaccel.transcoding.yml`, a file that doesn't exist anywhere in the repo, and the ML service extended a nonexistent `hwaccel` service name instead of the real `openvino` one in `hwaccel.ml.yml`) — see [Gitea issue #48](https://gitea.hughboi.cc/hughboi/homelab/issues/48).

## Network Layout

- `immich` network: internal — all four services communicate on it
- `proxy` network: immich-server joins this for Traefik routing

## Volumes

| Mount | Purpose |
|---|---|
| `/home/hughboi/data/immich/upload/` | Uploaded photos and videos (the main library) |
| `/mnt/truenas/immich` | External media library (read-only NFS mount) |
| `/etc/localtime:ro` | Timezone sync |
| `immich-cache` | ML model cache |
| `immich-postgres` | PostgreSQL data |

## Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `IMMICH_VERSION` | Image tag to use — defaults to `v2.7.5` if unset |
| `DB_PASSWORD` | Postgres password |
| `DB_USERNAME` | Postgres user |
| `DB_DATABASE_NAME` | Database name |
| `DB_STORAGE_TYPE` | `SSD` or `HDD` — tunes Postgres for the storage type |
| `REDIS_HOSTNAME` | `immich_redis` (matches container name) |

## First Run

1. Fill in `.env`
2. `docker compose up -d`
3. Navigate to https://immich.hughboi.cc
4. Create the admin account on the welcome screen
5. Install the Immich mobile app and configure server URL to `https://immich.hughboi.cc`
6. Enable automatic backup in the app settings

## External Library

The TrueNAS NFS mount at `/mnt/truenas/immich` is configured as an external library. To set this up:

1. In Immich UI → Administration → External Libraries → Create Library
2. Set the path to `/external-media`
3. Enable periodic scans or trigger manually

## Mobile App Backup

The Immich app backs up photos automatically when on WiFi. The upload path on the host is `/home/hughboi/data/immich/upload/`. Verify NFS or local storage has enough space before enabling backup on a large library.

## Upgrade Notes

> **Critical:** Always upgrade the server and machine learning containers together. They must be on the same version.

The `IMMICH_VERSION` env var controls both images. To upgrade:
1. Update `IMMICH_VERSION` in `.env` to the new version (e.g. `v2.8.0`)
2. `docker compose pull && docker compose up -d`
3. The server runs DB migrations automatically on startup — check `docker logs immich_server` for success

Check the [Immich release notes](https://github.com/immich-app/immich/releases) — breaking migrations do occur between versions. Do not skip multiple major versions.

## Backup

The Postgres database is critical — it contains all photo metadata, albums, faces, and sharing state. The raw photo files in `upload/` are also irreplaceable.

```sh
# Backup DB
docker exec immich_postgres pg_dumpall -U $DB_USERNAME > immich-db-$(date +%F).sql

# Backup upload directory (via restic)
# Restic handles /home/hughboi/data/immich automatically
```

## Troubleshooting

**Machine learning jobs failing:**
- Check `docker logs immich_machine_learning`
- The ML container needs the model cache warmed up on first run — models download on first use, which takes a few minutes

**Photos not appearing after upload:**
- Trigger a library rescan: Administration → Jobs → Library → Run
- Check `docker logs immich_server` for processing errors

**Postgres connection errors:**
- Verify the DB container is healthy: `docker exec immich_postgres pg_isready`
- Check that `DB_*` env vars in `.env` match what's set in the postgres environment
