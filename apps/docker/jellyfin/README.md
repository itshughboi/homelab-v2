# Jellyfin

**URL:** https://jellyfin.hughboi.cc
**Docs:** https://jellyfin.org/docs/

Self-hosted media server. Streams Films, TV Shows, Music, and Concerts from TrueNAS NFS mounts. No subscription, no tracking, no telemetry.

## Stack

Single container. Runs as `1000:1000` (hughboi).

## Network Layout

- `proxy` network only — Traefik handles external access
- No database container — Jellyfin uses its own internal SQLite database stored in `/config`

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/jellyfinconfig` | `/config` | Jellyfin config, DB, metadata, thumbnails |
| `cache` (named volume) | `/cache` | Transcoding cache |
| `/home/hughboi/mnt/truenas/jellyfin/Films` | `/Films:ro` | Film library |
| `/home/hughboi/mnt/truenas/jellyfin/TVShows` | `/TVShows:ro` | TV library |
| `/home/hughboi/mnt/truenas/jellyfin/Music` | `/Music:ro` | Music library |
| `/home/hughboi/mnt/truenas/jellyfin/Concerts` | `/Concerts:ro` | Concert videos |

All media mounts are `:ro` — Jellyfin never writes to the media directories.

## GPU Transcoding

GPU hardware transcoding is currently commented out in compose. To enable:

1. Uncomment the `devices` section in compose:
```yaml
devices:
  - /dev/dri/renderD128:/dev/dri/renderD128
  - /dev/dri/card0:/dev/dri/card0
```
2. In Jellyfin UI → Dashboard → Playback → Transcoding, select the hardware acceleration type (VA-API for Intel/AMD)
3. Set the VA-API device to `/dev/dri/renderD128`
4. Restart the container

## NFS Mount Setup

The TrueNAS mounts are at `/home/hughboi/mnt/truenas/jellyfin/`. If the mounts aren't present, add to `/etc/fstab`:
```sh
10.10.10.5:/mnt/The\ Archive/jellyfin/Films    /home/hughboi/mnt/truenas/jellyfin/Films    nfs defaults 0 0
10.10.10.5:/mnt/The\ Archive/jellyfin/TVShows  /home/hughboi/mnt/truenas/jellyfin/TVShows  nfs defaults 0 0
```

## First Run

1. `docker compose up -d`
2. Navigate to https://jellyfin.hughboi.cc
3. Complete the setup wizard — add libraries pointing to `/Films`, `/TVShows`, `/Music`, `/Concerts`
4. Let the initial scan complete (can take a while for large libraries)

## Upgrade Notes

- Config and DB are in `/home/hughboi/data/jellyfinconfig`. Back this up before major version upgrades.
- Jellyfin does not have automatic DB migrations between all major versions — always check the [upgrade notes](https://jellyfin.org/docs/general/administration/upgrading/) first.
- The `cache` named volume can be safely deleted between upgrades — it will be rebuilt.

## Troubleshooting

**Media not appearing after adding library:**
- Trigger a manual library scan: Dashboard → Libraries → click the refresh icon
- Check that the NFS mounts are present on the host: `ls /home/hughboi/mnt/truenas/jellyfin/`

**Transcoding errors / playback stutters:**
- Without GPU transcoding, Jellyfin uses CPU for on-the-fly transcoding. High-bitrate 4K streams will be heavy. Enable GPU transcoding or reduce the client's max streaming bitrate.

**Permission denied on config directory:**
- `sudo chown -R 1000:1000 /home/hughboi/data/jellyfinconfig`
