# SearXNG

**URL:** https://search.hughboi.cc
**Docs:** https://docs.searxng.org/

Privacy-respecting metasearch engine. Aggregates results from Google, DuckDuckGo, Bing, Brave, and dozens of other engines without tracking or building a profile. Use it instead of going directly to any commercial search engine.

## Stack

Single container. Runs as root with specific capabilities (`CHOWN`, `SETGID`, `SETUID`, `FOWNER`) for first-run file ownership setup inside the container. This is a SearXNG requirement, not a choice.

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/searxng` | `/etc/searxng:rw` | SearXNG config and instance data (`settings.yml`, `uwsgi.ini`, `limiter.toml`) |

## Config Files

After first run, `/home/hughboi/data/searxng/` will contain:
- `settings.yml` — main config: engines, UI theme, language, categories, privacy settings
- `uwsgi.ini` — uWSGI worker config (threads/workers controlled by env vars)
- `limiter.toml` — rate limiting config (optional, good idea if publicly accessible)

## Environment Variables

| Variable | Purpose |
|---|---|
| `SEARXNG_BASE_URL` | Must match public URL: `https://search.hughboi.cc/` |
| `SEARXNG_UWSGI_WORKERS` | Number of uWSGI worker processes (default: 4) |
| `SEARXNG_UWSGI_THREADS` | Threads per worker (default: 4) |

## First Run

1. `docker compose up -d`
2. SearXNG creates default config files in `/home/hughboi/data/searxng/` on first start
3. Navigate to https://search.hughboi.cc — should be working immediately
4. Customize `settings.yml` to enable/disable engines, change theme, etc.
5. Restart after any `settings.yml` changes: `docker restart searxng`

## Enabling/Disabling Engines

In `settings.yml`, find the `engines:` section. To disable an engine:
```yaml
engines:
  - name: google
    disabled: true
```

## Secret Key

SearXNG requires a `secret_key` in `settings.yml` for security:
```yaml
server:
  secret_key: "CHANGE_THIS_TO_A_LONG_RANDOM_STRING"
```
Generate with: `openssl rand -hex 32`

If missing, SearXNG generates a random one on each start, which breaks session continuity.

## Upgrade Notes

- Config is in the bind-mounted `/home/hughboi/data/searxng/` directory. Backup before upgrading.
- SearXNG uses date-based image tags (`2026.5.17-<commit>`). Check the [release notes](https://github.com/searxng/searxng/releases) — engine breakage is common when upstream search engines change their APIs.

## Troubleshooting

**All results empty or engines returning errors:**
- Search engines change their APIs frequently. Check `docker logs searxng` for engine errors.
- Update the image to get the latest engine fixes — this is the most common fix.

**"Too many requests" from Google:**
- Google rate-limits SearXNG instances. Either reduce Google's weight in `settings.yml` or disable it and use Brave/DDG instead.

**Config file permissions errors on startup:**
- `sudo chown -R 1000:1000 /home/hughboi/data/searxng`
