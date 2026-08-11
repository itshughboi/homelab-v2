# Promgraftail — Observability Stack

The central metrics and logging stack for the homelab. All observability runs here.

See [loki/README.md](loki/README.md) for detailed Loki + Promtail setup.

## Services

| Container | Image | URL | Purpose |
|---|---|---|---|
| `grafana` | `grafana/grafana` | https://grafana.hughboi.cc | Dashboards and visualization |
| `loki` | `grafana/loki` | https://loki.hughboi.cc | Log aggregation and query |
| `prometheus` | `prom/prometheus` | `:9070` (host port, not via Traefik) | Metrics scraping and alerting |
| `alertmanager` | `quay.io/prometheus/alertmanager` | `:9093` (host port, not via Traefik) | Alert routing |
| `promtail` | `grafana/promtail` | — (no UI) | Log shipping to Loki |
| `influxdb` | `influxdb` | https://influxdb.hughboi.cc | Time-series DB for Telegraf/SNMP metrics |
| `telegraf` | `telegraf` | — (no UI) | SNMP + host metrics collector → InfluxDB |

> [!NOTE] Migrated into the repo (Aug 2026)
> This stack was reconciled from its old drifted location `/home/hughboi/promgraftail`
> into this git-tracked dir, matching the homelab convention: **app code here, runtime
> data under `/home/hughboi/data/`**. Grafana + InfluxDB data were preserved (moved);
> Loki's ~19G of historical logs were intentionally wiped and started fresh (they
> regenerate). Images were re-pinned to current stable versions. Config files are now
> mounted with relative `./` paths from this dir.

> [!NOTE] Alloy is not deployed yet
> `compose.yaml` has no `alloy` service — `alloy/config.alloy` exists only as prep work.
> Promtail is EOL, so swapping Promtail → Alloy is the planned Phase 2 (a deliberate
> separate change: port the scrape jobs, wire Prometheus remote-write, verify each stream).

All services are on the `promgraftail` internal Docker network. Grafana, Loki, and InfluxDB also join the `proxy` network for Traefik routing.

## Network Layout

```
Internet → Traefik → [grafana, loki, influxdb]
                            ↕
                    promgraftail network
                  [prometheus, alertmanager, promtail, telegraf]
                            ↕
              Other stacks (unifi, promgraftail → shared network)
```

Prometheus and alertmanager are **not** exposed via Traefik. Access them via SSH tunnel if needed.

## Config Files (all in this repo dir, mounted `./` relative)

| File | Service | Purpose |
|---|---|---|
| `prometheus/prometheus.yml` | prometheus | Scrape configs and alerting rules pointer |
| `prometheus/alert-rules.yml` | prometheus | Alert rule definitions |
| `prometheus/alertmanager.yml` | alertmanager | Alert routing (receivers, routes) |
| `loki/config.yaml` | loki | Loki storage and retention config |
| `promtail/config.yaml` | promtail | Log scrape targets and Loki push config |
| `telegraf/telegraf.conf` | telegraf | SNMP and host input configs |
| `alloy/config.alloy` | — | Not yet deployed (see note above) — file exists in the repo as prep work only, nothing reads it |

All config files are mounted `:ro` — restart the service after any config change.

## Grafana

**User:** admin (set password on first login)
**Runs as `user: "0"`** (root inside the container). The old stack tried UID 472 (Grafana's
default) but hit a write-permission issue on the data dir, so it runs as `0`. Revisit this
alongside the port-hardening work — ideally `chown -R 472:472 /home/hughboi/data/grafana` and
switch back to `user: "472"`.

### Data Sources

Add these in Grafana UI → Connections → Data Sources:
- **Prometheus:** `http://prometheus:9090`
- **Loki:** `http://loki:3100` (or `https://loki.hughboi.cc` with basic auth if auth is enabled)
- **InfluxDB:** `http://influxdb:8086` (internal) or `https://influxdb.hughboi.cc`

### Useful Dashboards

Import by ID from grafana.com:
- **Node Exporter Full:** 1860
- **UniFi Poller:** 11315
- **Docker:** 179
- **Loki Logs:** 13639

## Prometheus

Config at `prometheus.yml`. Key scrape jobs:
- `node_exporter` — host metrics
- `unifipoller` — scrapes unifi-poller container on the `promgraftail` network (no host port needed — container-to-container)
- `cadvisor` — Docker container metrics; the service block is present in `compose.yaml` but **fully commented out**, not currently running. Uncomment and redeploy if container-level metrics are wanted.

Alertmanager is configured in `prometheus.yml`:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

## Promtail

Scrapes:
- `/var/log` on dock-prod and the pve-srv-* hosts (syslog, auth.log, etc.)
- Docker container logs via `docker.sock`
- `bind9` syslog receiver on port `1514` (published as `1541:1514`)

> The old `unbound_logs` scrape job was **removed** during the migration — its source
> path (`/home/hughboi/adguard/unbound/unbound.log`) was deleted when AdGuard migrated.
> Unbound log shipping returns with the AdGuard/unbound observability work (unbound
> currently logs to a file inside its own container; needs a shared path or stdout first).

## Telegraf

Runs as `telegraf:988` (the telegraf group on the host, needed for docker.sock access). Collects:
- Host system metrics (CPU, memory, disk, network) via host filesystem mounts
- SNMP metrics (configured in `telegraf.conf`) → pushed to InfluxDB

## InfluxDB

- Web UI on https://influxdb.hughboi.cc
- Also accessible on `127.0.0.1:8086` from the host
- Port `8089/udp` is for the InfluxDB line protocol UDP listener

Initial setup is done through the web UI — creates the org, bucket, and admin token on first run. Store the admin token in `.env` after generation.

## Alloy (not yet deployed)

Grafana Alloy is the planned next-gen OTel collector to replace Promtail — it can ingest logs, metrics, and traces. A config file exists at `alloy/config.alloy` as prep work, but there is no `alloy` service in `compose.yaml` yet, so none of this is live: no container, no `https://alloy.hughboi.cc` route, nothing listening on port 3100 or `12345`. Stand this up as part of the same dedicated future session as this stack's other real path/drift issues (see Troubleshooting below).

## Upgrade Notes

- Grafana: back up `/home/hughboi/data/grafana` before upgrading — contains dashboards, data source configs, users.
- Loki: back up `/home/hughboi/data/loki/data` — contains the log chunks and index.
- InfluxDB: back up `/home/hughboi/data/influxdb`.
- Prometheus, Alertmanager, Promtail, Telegraf: stateless config — no data to back up separately.

## Troubleshooting

**✅ Migration completed (Aug 2026):** the path/drift/version issues previously flagged here are
resolved. This stack now deploys from `/home/hughboi/homelab/apps/docker/promgraftail/` with
relative `./` config mounts, data under `/home/hughboi/data/`, live configs reconciled into the
repo (including the `bind9` syslog job), and images re-pinned to current stable versions. Two
version bumps required config fixes at the time: promtail's `bind9` syslog `labels:` had to move
*inside* the `syslog:` block, and telegraf's `inputs.docker` dropped the deprecated
`perdevice`/`total` fields (now `perdevice_include`/`total_include`).

**Still open (tracked as Gitea issues / future phases):**
1. **Port hardening** — published ports are currently exposed as they were live (e.g. `3100`,
   `8086`, `9070`, `9093`); binding them to `127.0.0.1` is deferred. See the Gitea issue.
2. **Promtail → Alloy** — Promtail is EOL; Phase 2 swaps it for Grafana Alloy (port scrape jobs,
   enable Prometheus remote-write — already turned on via `--web.enable-remote-write-receiver`).
3. **Not yet SOPS-migrated** — no `.env.sops` for this stack yet.
4. **Long-term uptime history** — a Blackbox exporter scraped by Prometheus would restore the
   historical uptime%/incident-timeline view that Uptime Kuma provided (Gatus only covers current
   status + a short window).

**Grafana can't connect to Prometheus:**
- Both must be on the `promgraftail` network. Verify: `docker network inspect promgraftail | grep -A2 prometheus`
- Test from Grafana container: `docker exec grafana wget -qO- http://prometheus:9090/-/ready`

**Logs not appearing in Loki:**
- Check Promtail is running and can reach Loki: `docker logs promtail`
- Check the Loki push endpoint: `curl http://localhost:3100/ready` (from host via port binding)

**Prometheus targets showing as down:**
- Navigate to `http://localhost:9070/targets` via SSH tunnel to see target status and error messages

**Alertmanager not sending alerts:**
- Check routing config in `alertmanager.yml`
- Test with `amtool` from inside the container: `docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml`
