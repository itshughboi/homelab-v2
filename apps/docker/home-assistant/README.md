# Home Assistant

**URL:** https://home-assistant.hughboi.cc
**Docs:** https://www.home-assistant.io/docs/

Home automation platform. Integrates with smart devices, sensors, and external services to automate and monitor the home. Core of any smart home setup.

## Stack

Two containers:

| Container | Image | Role |
|---|---|---|
| `home-assistant` | `ghcr.io/home-assistant/home-assistant` | Main HA application |
| `homeassistant-db` | `postgres:16.3` | Long-term stats and history storage |

HA uses Postgres as the recorder database for long-term history. Without Postgres, the built-in SQLite recorder fills up and HA slows down significantly over time.

## Network Layout

- `home-assistant` network: internal — only HA and Postgres on it
- `proxy` network: HA joins this to be accessible via Traefik

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./config` (this repo checkout) | `/config` | HA config directory — `configuration.yaml`, `secrets.yaml`, integrations, automations, scripts |
| `/etc/localtime` | `/etc/localtime:ro` | Host timezone sync |
| `db` (named volume) | `/var/lib/postgresql/data` | Postgres data |

## Secrets (SOPS)

Two separate secret files, both SOPS-encrypted:

- `.env` (`.env.sops`) — `POSTGRES_USER`/`POSTGRES_PASSWORD` for the `homeassistant-db` container itself
- `config/secrets.yaml` (`config/secrets.yaml.sops`, config-as-secret pattern) — `postgres_user`/`postgres_password`/`recorder_db_url`, referenced from `configuration.yaml` via HA's native `!secret` mechanism (**not** `${VAR}` shell-style interpolation — HA's YAML parser doesn't expand that). Tracked placeholder is `config/secrets.yaml.example`.

## Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` | DB username for the recorder |
| `POSTGRES_PASSWORD` | DB password |

`TZ` is hardcoded in `compose.yaml` (`America/Denver`), not read from `.env`.

## Postgres Recorder Setup

In `configuration.yaml`, the recorder is configured via `!secret`, not literal values:
```yaml
recorder:
  db_url: !secret recorder_db_url
  purge_keep_days: 30
```

`recorder_db_url` itself lives in `config/secrets.yaml` (real: `postgresql://<user>:<password>@homeassistant-db/homeassistant-db`). Without this, HA uses SQLite which will slow down over time with history data.

Also required in `configuration.yaml`: `http.trusted_proxies` must include Traefik's real Docker network IP (`172.23.0.0/16`, not just the LAN `10.10.10.0/24`) — without it HA returns HTTP 400 on every request routed through Traefik. Confirm Traefik's actual IP with `docker inspect traefik --format '{{json .NetworkSettings.Networks}}'` if this ever needs re-verifying (bridge-network IPs can shift on container recreation).

## First Run

1. `git pull`, decrypt secrets via the `sops-deploy` Semaphore Task Template (or `./scripts/sops-run.sh home-assistant config` to verify locally)
2. `docker compose up -d`
3. Navigate to https://home-assistant.hughboi.cc
4. Complete the onboarding wizard — set location, timezone, account
5. Add the Postgres recorder config (`!secret recorder_db_url`) to `configuration.yaml` and restart HA

## Upgrade Notes

- HA releases very frequently (multiple times a month). Check the [release notes](https://www.home-assistant.io/blog/categories/release-notes/) before upgrading — breaking changes to integrations do occur.
- The image is pinned to a specific version. Update the tag in compose when upgrading deliberately.
- Always back up `apps/docker/home-assistant/config/` before upgrading. HA creates a backup automatically before upgrade if you use the update process inside the UI, but since we're running in Docker, do it manually.

## Backup

```sh
tar -czf ha-config-$(date +%F).tar.gz apps/docker/home-assistant/config/
```

Restic backs up all of `/home/hughboi` automatically, including this repo checkout — a manual tarball is only needed for an ad-hoc pre-upgrade snapshot.

## Troubleshooting

**HA can't connect to Postgres:**
- Check the recorder db_url in `configuration.yaml` — hostname must be `homeassistant-db` (the container name on the internal network)
- Verify Postgres is healthy: `docker exec homeassistant-db pg_isready -U $POSTGRES_USER`

**Integrations disappearing after restart:**
- Usually a config syntax error. Check `docker logs home-assistant` for YAML errors on startup

**Slow UI / high CPU after running for weeks:**
- The recorder is likely writing to SQLite instead of Postgres, or the history retention is too long. Verify `recorder.db_url` is set correctly in `configuration.yaml`
