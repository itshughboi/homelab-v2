# RomM

**URL:** https://romm.hughboi.cc
**Docs:** https://docs.romm.app/

ROM Manager. Organize, browse, and download game ROMs from a web interface. Pulls metadata, artwork, and descriptions from IGDB, SteamGridDB, Hasheous, and RetroAchievements.

> [!NOTE] Real deployment drift (found 2026-07-17, not yet fixed)
> Production runs this stack from `/home/hughboi/romm/docker-compose.yml` on
> dock-prod, not from this repo checkout, and several mounts have drifted:
> - `mysql` is actually a **named Docker volume** (`romm_mysql_data`) in
>   production — the repo's `compose.yaml` declares it as a bind mount
>   (`/home/hughboi/data/romm/mysql:/var/lib/mysql`) that doesn't exist and
>   isn't tracked as a `volumes:` entry at all. This is the ROM metadata/user
>   database — highest-stakes part of this drift.
> - `assets`/`library` real paths are `/home/hughboi/romm/{assets,library}`,
>   not the repo's `/home/hughboi/data/romm/{library,assets}`.
> - `config.yml` real path is `/home/hughboi/romm/config/config.yml`, not the
>   repo's `/home/hughboi/code/romm/config/config.yml`.
> - The two already-named volumes (`romm_resources`, `romm_redis_data`) are
>   real in production too, but prefixed with the project name twice
>   (`romm_romm_resources`, `romm_romm_redis_data`) since the real compose
>   project is also named `romm` — same class of prefix collision handled for
>   tube-archivist and paperless-ngx (see their git history, 2026-07-17, for
>   the volume-copy pattern to follow: stop stack, create correctly-named
>   volumes, `docker run --rm -v old:/from -v new:/to alpine cp -a`, verify
>   file counts match, redeploy, remove old volumes).
> Not yet SOPS-migrated — do this reconciliation first, same diff-first
> discipline as every other service this session (assume the live host is
> the source of truth, not the repo).

## Stack

Two containers:

| Container | Role |
|---|---|
| `romm` | Main app + web UI |
| `romm-db` | MariaDB 11 — ROM metadata, user data, play stats |

## Network Layout

- `romm` network: internal — app and MariaDB communicate here
- `proxy` network: app joins this for Traefik routing

## Volumes

| Mount | Purpose |
|---|---|
| `romm_resources` (named volume) | Downloaded artwork and metadata |
| `romm_redis_data` (named volume) | Redis data (embedded in romm container) |
| `/home/hughboi/data/romm/library` | ROM files — organized by platform |
| `/home/hughboi/data/romm/assets` | User-uploaded assets |
| `/home/hughboi/code/romm/config/config.yml` | RomM config — platforms, scrapers, auth |

## Key Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `DB_PASSWD` | MariaDB password for romm-user |
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |
| `ROMM_AUTH_SECRET_KEY` | Secret for session signing — `openssl rand -hex 32` |
| `IGDB_CLIENT_ID` / `IGDB_CLIENT_SECRET` | IGDB API credentials for metadata |
| `STEAMGRIDDB_API_KEY` | SteamGridDB API key for artwork |
| `RETROACHIEVEMENTS_API_KEY` | RetroAchievements API key |

## IGDB API Credentials

Required for metadata scraping. Get from https://api.igdb.com/:
1. Create a Twitch app at https://dev.twitch.tv/console
2. Copy the Client ID and Client Secret to `.env`

## Library Structure

RomM expects ROMs organized by platform name. It creates the correct folder structure automatically when you upload via the UI. Manual structure:
```
/home/hughboi/data/romm/library/
├── gba/
│   └── game.gba
├── ps1/
│   └── game.bin
└── snes/
    └── game.sfc
```

---

## Installation
1. Clone repo
2. Edit .env files
3. Stand up docker compose
4. Start uploading + playing

## Directory strucutre
- Romm itself will create the proper folder structure once you pull it. When you upload in the UI and pick the 'GBA' type e.g. it will automatically create the correct GBA directory. So I shouldn't have to create any files or directories outside of the docker-compose.yaml and the .env file

## Hasheous (RetroAchievments)
https://docs.romm.app/4.5.0/Getting-Started/Metadata-Providers/#retroachievements/
