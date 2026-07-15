# Homepage

**URL:** https://home.hughboi.cc
**Docs:** https://gethomepage.dev/

Homelab dashboard. Shows widgets for all services with live stats — Proxmox node status, TrueNAS pool health, Unifi client counts, Grafana, Gitea, PBS, Immich, etc.

## Stack

Single container. Config is managed in the repo under `/home/hughboi/code/homepage/config/`.

## Network Layout

- `proxy` network: for Traefik
- `homepage` network: external (pre-created) — this is used when Docker socket integration is enabled so Homepage can discover and display container statuses

## Config Files

All config lives in `/home/hughboi/code/homepage/config/`:

| File | Purpose |
|---|---|
| `services.yaml` | Service tiles and their widgets |
| `bookmarks.yaml` | Bookmark links |
| `widgets.yaml` | Top-bar info widgets (date, search, system stats) |
| `settings.yaml` | Theme, layout, language, title |
| `docker.yaml` | Docker integration config (if docker.sock enabled) |

Config changes take effect immediately — Homepage watches the config directory and hot-reloads.

## Environment Variables (Widget Credentials)

All are passed as `HOMEPAGE_VAR_*` and referenced in `services.yaml` as `{{HOMEPAGE_VAR_NAME}}`:

| Variable | Service |
|---|---|
| `HOMEPAGE_VAR_PROXMOX_USERNAME` / `_PASSWORD` | Proxmox node stats |
| `HOMEPAGE_VAR_TRUENAS_KEY` | TrueNAS API key |
| `HOMEPAGE_VAR_ADGUARD_USERNAME` / `_PASSWORD` | AdGuard stats |
| `HOMEPAGE_VAR_UNIFI_USERNAME` / `_PASSWORD` | UniFi controller |
| `HOMEPAGE_VAR_IMMICH_KEY` | Immich API key |
| `HOMEPAGE_VAR_GITEA_KEY` | Gitea API token |
| `HOMEPAGE_VAR_PBS_USERNAME` / `_PASSWORD` | Proxmox Backup Server |
| `HOMEPAGE_VAR_GRAFANA_USERNAME` / `_PASSWORD` | Grafana widget |
| `HOMEPAGE_VAR_PORTAINER_KEY` | Portainer API token |
| `HOMEPAGE_VAR_TAILSCALE_KEY` | Tailscale widget |
| `HOMEPAGE_VAR_AUTHENTIK_KEY` | Authentik user count widget |
| `HOMEPAGE_VAR_PAPERLESS_KEY` | Paperless-ngx API key |
| `HOMEPAGE_VAR_FILEBROWSER_USERNAME` / `_PASSWORD` | File Browser widget |
| `HOMEPAGE_ALLOWED_HOSTS` | Must include `home.hughboi.cc` to prevent host validation errors |

## Adding a New Service Widget

1. Edit `/home/hughboi/code/homepage/config/services.yaml`
2. Add the service under the appropriate group. Example:
```yaml
- My Service:
    href: https://myservice.hughboi.cc
    icon: myservice.png
    widget:
      type: myservice
      url: http://myservice:port
      key: {{HOMEPAGE_VAR_MYSERVICE_KEY}}
```
3. Add the corresponding env var to `.env` and to compose
4. Homepage hot-reloads — no restart needed

## DNS

The container uses `10.10.10.10` (dock-prod, this host) and `10.10.10.8` (Bind9, on Athena) as DNS so it can resolve internal service hostnames for widget health checks.

## Upgrade Notes

- No persistent data — all config is in the repo. Upgrade is just a tag bump + `docker compose up -d`.
- Check [Homepage releases](https://github.com/gethomepage/homepage/releases) for any breaking changes to widget config schema.

## Troubleshooting

**Widget showing "Error" instead of data:**
- Check that the env var is populated: `docker exec homepage env | grep HOMEPAGE_VAR_SERVICE`
- Verify the service URL is reachable from inside the container

**"Unauthorized" on `home.hughboi.cc`:**
- Ensure `HOMEPAGE_ALLOWED_HOSTS` includes the hostname. Missing this causes a 400 error from Homepage's host validation middleware.

**Config changes not appearing:**
- Homepage hot-reloads from `/app/config`. If it's not reloading, check file permissions on the config mount: `sudo chown -R 1000:1000 /home/hughboi/code/homepage/config`
