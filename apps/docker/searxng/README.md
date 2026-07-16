# SearXNG

**URL:** https://search.hughboi.cc
**Docs:** https://docs.searxng.org/

Privacy-respecting metasearch engine. Aggregates results from Google, DuckDuckGo, Bing, Brave, and dozens of other engines without tracking or building a profile. Use it instead of going directly to any commercial search engine.

## Stack

Single container. Runs as root with specific capabilities (`CHOWN`, `SETGID`, `SETUID`, `FOWNER`) for first-run file ownership setup inside the container. This is a SearXNG requirement, not a choice.

Also sets `apparmor:unconfined` in `security_opt` — dock-prod runs AppArmor in enforce mode by
default, which conflicts with the CHOWN/SETUID/etc. caps above. Without it, first-run setup fails.

## Volumes

| Volume | Container Path | Purpose |
|---|---|---|
| `searxng-config` (named) | `/etc/searxng:rw` | SearXNG config and instance data (`settings.yml`, `uwsgi.ini`, `limiter.toml`) |
| `searxng-cache` (named) | `/var/cache/searxng` | Runtime cache |

These are Docker-managed named volumes, not host bind mounts — inspect with
`docker volume inspect searxng_searxng-config` (prefixed with the compose project name) rather
than looking for files under `apps/docker/searxng/` or any `/home/hughboi/...` path. (An earlier
version of this compose file bind-mounted a host path, but three different, mutually
inconsistent paths were found in circulation — the repo's own claim, production's on-disk
compose file, and the actual live mount per `docker inspect` all disagreed. Reset to named
volumes rather than chase down which was authoritative.)

## Config Files

After first run, the `searxng-config` volume will contain:
- `settings.yml` — main config: engines, UI theme, language, categories, privacy settings
- `uwsgi.ini` — uWSGI worker config (threads/workers controlled by env vars)
- `limiter.toml` — rate limiting config (optional, good idea if publicly accessible)

To edit these, either `docker exec -it searxng sh` and edit in place, or
`docker cp searxng:/etc/searxng/settings.yml .`, edit, `docker cp` back, then restart.

## Environment Variables

| Variable | Purpose |
|---|---|
| `SEARXNG_BASE_URL` | Must match public URL: `https://search.hughboi.cc/` |
| `SEARXNG_UWSGI_WORKERS` | Number of uWSGI worker processes (default: 4) |
| `SEARXNG_UWSGI_THREADS` | Threads per worker (default: 4) |

## First Run

1. `docker compose up -d`
2. SearXNG creates default config files in the `searxng-config` volume on first start
3. Navigate to https://search.hughboi.cc — should be working immediately
4. Customize `settings.yml` to enable/disable engines, change theme, etc. (see Config Files above for how to edit)
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

- Config lives in the `searxng-config` named volume. Back it up with the pattern in
  [docs/Backup-Recovery.md](../../../docs/Backup-Recovery.md#ad-hoc-back-up-a-docker-named-volume-before-a-risky-change)
  before upgrading if you've made meaningful `settings.yml` customizations.
- SearXNG uses date-based image tags (`2026.5.17-<commit>`). Check the [release notes](https://github.com/searxng/searxng/releases) — engine breakage is common when upstream search engines change their APIs.

## Troubleshooting

**All results empty or engines returning errors:**
- Search engines change their APIs frequently. Check `docker logs searxng` for engine errors.
- Update the image to get the latest engine fixes — this is the most common fix.

**"Too many requests" from Google:**
- Google rate-limits SearXNG instances. Either reduce Google's weight in `settings.yml` or disable it and use Brave/DDG instead.

**First-run fails with a file ownership/permission error inside the container:**
- Confirm `apparmor:unconfined` is still present in `compose.yaml`'s `security_opt` — if dock-prod's
  AppArmor is in enforce mode (check with `sudo aa-status`) and this is missing, the CHOWN/SETUID
  capabilities SearXNG needs for first-run setup get blocked.
