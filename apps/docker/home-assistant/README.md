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
| `/config` | `/config` | HA config directory — `configuration.yaml`, integrations, automations, scripts |
| `/etc/localtime` | `/etc/localtime:ro` | Host timezone sync |
| `db` (named volume) | `/var/lib/postgresql/data` | Postgres data |

The `/config` directory on the host is where all HA configuration lives. This is what gets backed up.

## Environment Variables

| Variable | Purpose |
|---|---|
| `TZ` | Timezone (`America/Denver`) |
| `POSTGRES_USER` | DB username for the recorder |
| `POSTGRES_PASSWORD` | DB password |
| `POSTGRES_DB` | DB name (`homeassistant-db`) |

## Postgres Recorder Setup

In `configuration.yaml`, configure the recorder to use Postgres:
```yaml
recorder:
  db_url: postgresql://USERNAME:PASSWORD@homeassistant-db:5432/homeassistant-db
  purge_keep_days: 30
```

Without this, HA uses SQLite which will slow down over time with history data.

## First Run

1. Fill in `.env` with Postgres credentials
2. `docker compose up -d`
3. Navigate to https://home-assistant.hughboi.cc
4. Complete the onboarding wizard — set location, timezone, account
5. Add the Postgres recorder config to `configuration.yaml` and restart HA

## Upgrade Notes

- HA releases very frequently (multiple times a month). Check the [release notes](https://www.home-assistant.io/blog/categories/release-notes/) before upgrading — breaking changes to integrations do occur.
- The image is pinned to a specific version. Update the tag in compose when upgrading deliberately.
- Always back up `/config` before upgrading. HA creates a backup automatically before upgrade if you use the update process inside the UI, but since we're running in Docker, do it manually.

## Backup

```sh
tar -czf ha-config-$(date +%F).tar.gz /config
```

Restic handles this automatically via the backup container.

## Troubleshooting

**HA can't connect to Postgres:**
- Check the recorder db_url in `configuration.yaml` — hostname must be `homeassistant-db` (the container name on the internal network)
- Verify Postgres is healthy: `docker exec homeassistant-db pg_isready -U $POSTGRES_USER`

**Integrations disappearing after restart:**
- Usually a config syntax error. Check `docker logs home-assistant` for YAML errors on startup

**Slow UI / high CPU after running for weeks:**
- The recorder is likely writing to SQLite instead of Postgres, or the history retention is too long. Verify `recorder.db_url` is set correctly in `configuration.yaml`
