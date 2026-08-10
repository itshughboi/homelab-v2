# Homepage

**URL:** https://home.hughboi.cc
**Docs:** https://gethomepage.dev/

Homelab dashboard. Mostly link tiles (href + status dot) grouped by category, with live **Proxmox** node widgets (VM count, CPU, memory) at the top and a Glances CPU chart. Previously had widgets for many services (TrueNAS, Unifi, Grafana, PBS, Immich, etc.) — those were removed in favor of a simpler, faster dashboard; only Proxmox keeps a live widget.

## Stack

Single container. Config is managed in the repo under `/home/hughboi/homelab/apps/docker/homepage/config/`.

## Network Layout

- `proxy` network: for Traefik
- `homepage` network: external (pre-created) — this is used when Docker socket integration is enabled so Homepage can discover and display container statuses

## Config Files

All config lives in `/home/hughboi/homelab/apps/docker/homepage/config/`:

| File | Purpose |
|---|---|
| `services.yaml` | Service tiles and their widgets |
| `bookmarks.yaml` | Bookmark links |
| `widgets.yaml` | Top-bar info widgets (date, search, system stats) |
| `settings.yaml` | Theme, layout, language, title |
| `docker.yaml` | Docker integration config (if docker.sock enabled) |

Config changes take effect immediately — Homepage watches the config directory and hot-reloads.

## Environment Variables (Widget Credentials)

Passed as `HOMEPAGE_VAR_*` and referenced in `services.yaml` as `{{HOMEPAGE_VAR_NAME}}`.
Since the dashboard was slimmed to link tiles, only the Proxmox widget needs
credentials:

| Variable | Service |
|---|---|
| `HOMEPAGE_VAR_PROXMOX_USERNAME` / `_PASSWORD` | Proxmox node widgets (API token, `api@pam!homepage` style) |
| `HOMEPAGE_ALLOWED_HOSTS` | Must include `home.hughboi.cc` to prevent host validation errors |

### Secrets are SOPS-encrypted

These live in `.env.sops` (encrypted, committed) — **not** a plaintext `.env`.
Deploy through the SOPS flow so the values get decrypted and injected:

- **Via Semaphore:** `sops-deploy` Task Template, service `homepage`, Limit `dock-prod`.
- **By hand on dock-prod:** `./scripts/sops-run.sh homepage up -d` (decrypts in
  memory — **not** plain `docker compose up -d`, which would leave the
  `{{HOMEPAGE_VAR_PROXMOX_*}}` unresolved and the Proxmox widgets failing auth).

To change a value: edit the real `.env` on a host with the age key (Athena),
re-run `./scripts/sops-migrate.sh homepage`, commit the updated `.env.sops`.

## Adding a New Service Widget

1. Edit `/home/hughboi/homelab/apps/docker/homepage/config/services.yaml`
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

3. If the widget needs a credential, add the var to the real `.env` (on Athena),
   re-encrypt with `./scripts/sops-migrate.sh homepage`, and add the passthrough
   line to compose's `environment:` block
4. Redeploy via the SOPS flow (see above) — Homepage hot-reloads config, but a
   new secret needs the deploy to inject it

## DNS

The container uses `10.10.10.10` (dock-prod, this host) and `10.10.10.8` (Bind9, on Athena) as DNS so it can resolve internal service hostnames for widget health checks.

## Upgrade Notes

- No persistent data — all config is in the repo. Upgrade is a tag bump in `compose.yaml`, then redeploy via the SOPS flow (`sops-deploy` or `./scripts/sops-run.sh homepage up -d`), not plain `docker compose up -d`.
- Check [Homepage releases](https://github.com/gethomepage/homepage/releases) for any breaking changes to widget config schema.

## Troubleshooting

**Widget showing "Error" instead of data:**
- Check that the env var is populated: `docker exec homepage env | grep HOMEPAGE_VAR_SERVICE`
- Verify the service URL is reachable from inside the container

**"Unauthorized" on `home.hughboi.cc`:**
- Ensure `HOMEPAGE_ALLOWED_HOSTS` includes the hostname. Missing this causes a 400 error from Homepage's host validation middleware.

**Config changes not appearing:**
- Homepage hot-reloads from `/app/config`. If it's not reloading, check file permissions on the config mount: `sudo chown -R 1000:1000 /home/hughboi/homelab/apps/docker/homepage/config`
