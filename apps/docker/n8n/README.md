### Ideas
- Update my root-hints file for unbound every few months for most up to date info

---

# n8n

**URL:** https://n8n.hughboi.cc
**Docs:** https://docs.n8n.io/

Workflow automation platform. Build automations by connecting services — similar to Zapier but self-hosted. Used for automating homelab tasks: backup notifications, root.hints updates, monitoring alerts, etc.

## Stack

Two containers:

| Container | Image | Role |
|---|---|---|
| `n8n` | `n8nio/n8n` | Main app + workflow engine |
| `n8n-db` | `postgres:15` | Workflow definitions and execution history |

## Network Layout

- `n8n` network: internal — n8n and Postgres communicate here
- `proxy` network: n8n joins this for Traefik routing

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/n8n/data` | `/home/node/.n8n` | n8n config, credentials (encrypted), community nodes |
| `/home/hughboi/data/n8n/files` | `/files` | Files produced or consumed by workflows |
| `/home/hughboi/data/n8n/db` | `/var/lib/postgresql/data` | Postgres data |

## Key Environment Variables (`.env`, SOPS-encrypted as `.env.sops`)

| Variable | Purpose |
|---|---|
| `DOMAIN_NAME` | `hughboi.cc` |
| `SUBDOMAIN` | `n8n` |
| `GENERIC_TIMEZONE` | `America/Denver` |
| `N8N_HOST` | Hostname (`n8n.hughboi.cc`) |
| `N8N_PROTOCOL` | `https` |
| `WEBHOOK_URL` | Full public URL for webhooks: `https://n8n.hughboi.cc/` |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | For the Postgres container |

There is no `N8N_ENCRYPTION_KEY` or `DB_TYPE`/`DB_POSTGRESDB_HOST` set in this deployment's `.env`
— n8n falls back to its own defaults for those when unset. If credential-encryption backup ever
becomes a concern, n8n auto-generates and persists the encryption key inside its own data volume
(`/home/hughboi/data/n8n/data`) rather than requiring it as an env var.

## First Run

1. Fill in `.env`
2. `docker compose up -d`
3. Navigate to https://n8n.hughboi.cc
4. Create the owner account
5. Install community nodes if needed: **Settings → Community Nodes → Install**

## Credentials

n8n stores service credentials encrypted using `N8N_ENCRYPTION_KEY`. If this key is lost, all saved credentials become unreadable. Store it alongside a copy of the data volume backup.

## Webhooks

External services trigger workflows via:
```
https://n8n.hughboi.cc/webhook/<workflow-id>
```
Protect sensitive webhooks with n8n's built-in header auth or add an IP allowlist in Traefik.

## Upgrade Notes

- Back up `/home/hughboi/data/n8n/data` and dump the Postgres DB before upgrading.
- n8n has had breaking workflow schema changes between major versions. Check the [migration guide](https://docs.n8n.io/hosting/migration-guides/) before major version bumps.
- Export all workflows as JSON before a major upgrade: **Workflows → Export All**

## Postgres Backup

```sh
docker exec n8n-db pg_dump -U $POSTGRES_USER $POSTGRES_DB > n8n-db-$(date +%F).sql
```

## Troubleshooting

**Workflows not triggering from webhooks:**
- Verify the workflow is **Active** (toggle in top right of workflow editor)
- Confirm `WEBHOOK_URL` in `.env` matches the public URL

**Credentials showing as invalid after restart:**
- `N8N_ENCRYPTION_KEY` must be identical to what was in place when credentials were saved. If it changed, credentials are unreadable.

**Postgres connection refused on startup:**
- n8n waits for Postgres healthy before starting (`depends_on: condition: service_healthy`). Check `docker logs n8n-db` for startup errors.