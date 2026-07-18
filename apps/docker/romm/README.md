# RomM

**URL:** https://romm.hughboi.cc
**Docs:** https://docs.romm.app/

ROM Manager. Organize, browse, and download game ROMs from a web interface. Pulls metadata, artwork, and descriptions from IGDB, SteamGridDB, Hasheous, and RetroAchievements.

> [!NOTE] Reconciled 2026-07-18
> Real drift found 2026-07-17 (mysql was an unnamed-in-repo bind mount vs a
> real named volume in production, assets/library/config.yml paths didn't
> match) was fixed — see git history around commits `454c5e1`/`c40fa9a` for
> the full story, including a real Compose gotcha: declaring a volume name
> that happens to match what you manually pre-created isn't enough — Compose
> still prefixes it with the project name unless you add an explicit
> `name:` override, which is why `volumes:` below has one for all three.
> Also fixed a mount bug where `config.yml` was bound to a path that was
> actually a directory (`config.yml/config.yml`), an old Docker
> auto-created-directory mistake.
>
> The ROM library was relocated from local disk to a TrueNAS NFS export
> (`/mnt/truenas/romm`, backed by `The Archive/Gaming/Romm`) for reuse
> elsewhere — verified byte-for-byte (md5sum, all 44 files) before deleting
> the local copy. Upgraded 4.8.1 → 5.0.0 in the same pass, with a
> `mariadb-dump` backup taken first (`/home/hughboi/romm-backup-pre-5.0.0-*.sql`
> on dock-prod). SOPS-migrated.

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
| `romm_mysql_data` (named volume) | MariaDB data — ROM metadata, users, play stats |
| `/mnt/truenas/romm/library` | ROM files — organized by platform (TrueNAS-backed) |
| `/home/hughboi/romm/assets` | User-uploaded assets |
| `apps/docker/romm/config.yml` (this repo checkout) | RomM config — platforms, scrapers, auth |

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
/mnt/truenas/romm/library/
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

## Hasheous (RetroAchievments)
https://docs.romm.app/4.5.0/Getting-Started/Metadata-Providers/#retroachievements/
