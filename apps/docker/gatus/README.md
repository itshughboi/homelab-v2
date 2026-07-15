# Gatus

**URL:** https://gatus.hughboi.cc
**Docs:** https://gatus.io/

Uptime and health monitoring dashboard. Pings services on a configured schedule, tracks response times and status codes, and shows history graphs. My status page for knowing if anything in the homelab is down.

## Stack

Two containers: `gatus` and its own dedicated `gatus-postgres` (not a shared/external
Postgres — same one-database-per-app pattern as Gitea/Semaphore). `POSTGRES_USER`,
`POSTGRES_PASSWORD`, `POSTGRES_DB` are passed to both; `POSTGRES_ENDPOINT` is fixed
to `postgres:5432` (the Postgres container's name on the internal `gatus` Docker
network) and set directly in `compose.yaml`, not `.env` — it's not something you'd
ever need to change.

## Config

Config lives at `/home/hughboi/code/gatus/config` (mounted `:ro`). This is where all endpoints, alert rules, and thresholds are defined. Changes to config require a container restart to take effect.

DNS for the container is set to `10.10.10.8` (Bind9, on Athena) and `10.10.10.10` (dock-prod, this host) so that internal hostnames resolve correctly when checking internal services.

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/code/gatus/config` | `/config:ro` | Endpoint definitions and thresholds |

## First Run

1. Edit the config at `/home/hughboi/code/gatus/config/config.yaml`
2. Add endpoints to monitor — example:
```yaml
endpoints:
  - name: Vaultwarden
    url: https://vaultwarden.hughboi.cc
    interval: 5m
    conditions:
      - "[STATUS] == 200"
      - "[RESPONSE_TIME] < 3000"
    alerts:
      - type: discord
```
3. `docker compose up -d`
4. Navigate to https://gatus.hughboi.cc

## Alerting

Configure alert providers in the config YAML. Options: Discord, ntfy, PagerDuty, Slack, email. The Discord webhook and ntfy endpoint can be defined as env vars and referenced with `${VARIABLE}` in the config.

## Upgrade Notes

- Config is code (in the repo) so no data migration needed — just update the image tag and restart.
- Review the [Gatus changelog](https://github.com/TwiN/gatus/releases) for any config schema changes before upgrading.

## Troubleshooting

**Service shows as down but is actually up:**
- Check the DNS resolution from inside the container: `docker exec gatus nslookup service.hughboi.cc`
- The container uses Bind9 and dock-prod's own resolver as DNS (10.10.10.8/10.10.10.10). If Bind9 is down, all internal checks will fail.

**Config changes not taking effect:**
- Gatus reads config only at startup. Restart the container after any config file change: `docker restart gatus`
