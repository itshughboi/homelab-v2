# Tube Archivist

**URL:** https://yt.hughboi.cc
**Docs:** https://docs.tubearchivist.com/

Self-hosted YouTube archiver. Subscribe to channels, download videos (audio + video or audio-only), and browse them from a local media library. Replaces depending on YouTube's availability for content I want to keep.

## Stack

| Container | Role |
|---|---|
| `tube-archivist` | Main app + download scheduler |
| `archivist-es` | Elasticsearch — full-text search index |
| `archivist-redis` | Redis — task queue for downloads |

## Network Layout

- `archivist` network: internal — all three containers communicate here
- `proxy` network: app joins this for Traefik routing

## Volumes

| Mount | Purpose |
|---|---|
| `/mnt/truenas/yt-audios` | TrueNAS NFS mount — all downloaded videos/audio stored here |
| `cache` (named volume) | App cache |
| `redis` (named volume) | Redis data |
| `es` (named volume) | Elasticsearch index |

## Key Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `TA_HOST` | Public hostname: `yt.hughboi.cc` |
| `TA_USERNAME` | Admin username |
| `TA_PASSWORD` | Admin password |
| `ES_PASSWORD` | Elasticsearch password |
| `HOST_UID` / `HOST_GID` | File ownership for downloaded files (should match TrueNAS) |

## First Run

1. Fill in `.env`
2. `docker compose up -d` (wait for Elasticsearch to become healthy — can take 60+ seconds)
3. Navigate to https://yt.hughboi.cc
4. Log in with `TA_USERNAME` and `TA_PASSWORD`
5. Go to **Settings → Application** and configure download quality, thumbnails, etc.
6. Add channels to subscribe to under **Channels → Add**

## Upgrade Notes

- Tube Archivist pins to a specific version tag. Check the [changelog](https://github.com/tubearchivist/tubearchivist/releases) for Elasticsearch version requirements before upgrading — TA occasionally requires a specific ES version.
- The `es` named volume holds the search index. If Elasticsearch is upgraded to an incompatible version, the index must be rebuilt (done automatically but takes time for large libraries).

---

- Taken from official documentation: https://github.com/tubearchivist/tubearchivist

## Permissions for elasticsearch

If you see a message similar to Unable to access 'path.repo' (/usr/share/elasticsearch/data/snapshot) or failed to obtain node locks, tried [/usr/share/elasticsearch/data] and maybe these locations are not writable when initially starting elasticsearch, that probably means the container is not allowed to write files to the volume. To fix that issue, shutdown the container and on your host machine run:
```
chown 1000:0 -R /path/to/mount/point
```

This will match the permissions with the UID and GID of elasticsearch process within the container and should fix the issue.

*** 
<br>

## Truenas Connection

1. Mounting locally via NFS
```sh
sudo nano /etc/fstab
```

Add the following: (Reaplce YT-Audios with whatever TrueNAS dataset is called, and what you want local folder to be called under /mnt). \040 is there to ignore the space in the TrueNAS pool name. Using double quotes to make it a string doesn't always work either. Copy exactly as below.
```sh
10.10.10.5:/mnt/The\040Archive/YT-Audios /mnt/truenas/yt-audios nfs defaults 0 0
```

Then run this to mount it:
```sh
sudo mount -a
```

#### TrueNAS Permissions
- Tube Archivist runs as root user. On TrueNAS, on the NFS share, set **mapall user** to root. Then under Dataset -> Permissions, give root full access to the dataset