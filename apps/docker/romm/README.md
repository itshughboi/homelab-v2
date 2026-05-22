# RomM

**URL:** https://romm.hughboi.cc
**Docs:** https://docs.romm.app/

ROM Manager. Organize, browse, and download game ROMs from a web interface. Pulls metadata, artwork, and descriptions from IGDB, SteamGridDB, Hasheous, and RetroAchievements.

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
