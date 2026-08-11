# Promgraftail — Observability Stack

The central metrics and logging stack for the homelab. All observability runs here.

See [loki/README.md](loki/README.md) for detailed Loki setup (log collection is via Alloy — see the Alloy section below).

## Services

| Container | Image | URL | Purpose |
|---|---|---|---|
| `grafana` | `grafana/grafana` | https://grafana.hughboi.cc | Dashboards and visualization |
| `loki` | `grafana/loki` | https://loki.hughboi.cc | Log aggregation and query |
| `prometheus` | `prom/prometheus` | `:9070` (host port, not via Traefik) | Metrics scraping and alerting |
| `alertmanager` | `quay.io/prometheus/alertmanager` | `:9093` (host port, not via Traefik) | Alert routing |
| `alloy` | `grafana/alloy` | `127.0.0.1:12345` UI / `alloy.hughboi.cc` | Log collection → Loki (replaced promtail) |
| `influxdb` | `influxdb` | https://influxdb.hughboi.cc | Time-series DB for Telegraf/SNMP metrics |
| `telegraf` | `telegraf` | — (no UI) | SNMP + host metrics collector → InfluxDB |

> [!NOTE] Migrated into the repo (Aug 2026)
> This stack was reconciled from its old drifted location `/home/hughboi/promgraftail`
> into this git-tracked dir, matching the homelab convention: **app code here, runtime
> data under `/home/hughboi/data/`**. Grafana + InfluxDB data were preserved (moved);
> Loki's ~19G of historical logs were intentionally wiped and started fresh (they
> regenerate). Images were re-pinned to current stable versions. Config files are now
> mounted with relative `./` paths from this dir.

> [!NOTE] Promtail → Alloy (done, 2026-08)
> Log collection runs on **Grafana Alloy** (`alloy` service, config at
> `alloy/config.alloy`). It replaced the EOL Promtail, which is archived at
> `apps/docker/sunset/promtail/`. Alloy ships: dock-prod `/var/log/*`, bind9
> syslog (`:1541→1514`), and the AdGuard query log (JSON). Container logs are
> **not** scraped by Alloy — they ship via the Docker `loki` logging driver
> already (scraping them too would double-ship every line).

All services are on the `promgraftail` internal Docker network. Grafana, Loki, and InfluxDB also join the `proxy` network for Traefik routing.

## Network Layout

```
Internet → Traefik → [grafana, loki, influxdb, alloy]
                            ↕
                    promgraftail network
                  [prometheus, alertmanager, alloy, telegraf]
                            ↕
              Other stacks (unifi, unbound-exporter → shared network)
```

Prometheus and alertmanager are **not** exposed via Traefik. Access them via SSH tunnel if needed.

## Config Files (all in this repo dir, mounted `./` relative)

| File | Service | Purpose |
|---|---|---|
| `prometheus/prometheus.yml` | prometheus | Scrape configs and alerting rules pointer |
| `prometheus/alert-rules.yml` | prometheus | Alert rule definitions |
| `prometheus/alertmanager.yml` | alertmanager | Alert routing (receivers, routes) |
| `loki/config.yaml` | loki | Loki storage and retention config |
| `alloy/config.alloy` | alloy | Log collection: varlogs, bind9 syslog, AdGuard querylog → Loki |
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

## Alloy (log collector)

Grafana Alloy is this stack's log collector (replaced Promtail, which is now
sunset — see `apps/docker/sunset/promtail/`). Config: `alloy/config.alloy`.
UI at `127.0.0.1:12345` (also `alloy.hughboi.cc`).

Ships to Loki:
- **dock-prod `/var/log/*log`** (`loki.source.file "varlogs"`, label `job=dock-prod_varlogs`)
- **bind9 syslog** received on `:1514` (published `1541:1514`, TCP+UDP)
- **AdGuard query log** JSON (`loki.process "adguard"`) — client/blocked/qtype labels,
  raw JSON kept as the log body for `| json` in Grafana

Deliberately **not** collected by Alloy:
- **Container logs** — already shipped by the Docker `loki` logging driver on each
  container (`container_name`/`compose_service` labels). Scraping them in Alloy too
  would double-ship every line.
- **unbound logs** — unbound logs to a file inside its own container; re-adding this
  needs a shared path or stdout first (future work). unbound *metrics* are covered
  separately by `unbound-exporter` (see the adguard stack + `unbound` Prometheus job).

Optional host/docker **metrics** sections are present but commented out in
`config.alloy` — enabling them is a separate decision from the log collection.

## Telegraf

Runs as `telegraf:988` (the telegraf group on the host, needed for docker.sock access). Collects:
- Host system metrics (CPU, memory, disk, network) via host filesystem mounts
- SNMP metrics (configured in `telegraf.conf`) → pushed to InfluxDB

## InfluxDB

- Web UI on https://influxdb.hughboi.cc
- Also accessible on `127.0.0.1:8086` from the host
- Port `8089/udp` is for the InfluxDB line protocol UDP listener

Initial setup is done through the web UI — creates the org, bucket, and admin token on first run. Store the admin token in `.env` after generation.

## Upgrade Notes

- Grafana: back up `/home/hughboi/data/grafana` before upgrading — contains dashboards, data source configs, users.
- Loki: back up `/home/hughboi/data/loki/data` — contains the log chunks and index.
- InfluxDB: back up `/home/hughboi/data/influxdb`.
- Prometheus, Alertmanager, Alloy, Telegraf: stateless config — no data to back up separately (Alloy keeps only file-tail positions in the `alloy_data` volume).

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
2. ~~**Promtail → Alloy**~~ — DONE (2026-08). Alloy is the log collector; Promtail archived in
   `apps/docker/sunset/promtail/`. Prometheus has `--web.enable-remote-write-receiver` enabled so
   Alloy *could* also push host/docker metrics (sections are commented out in `config.alloy`).
3. **Not yet SOPS-migrated** — no `.env.sops` for this stack yet.
4. **Long-term uptime history** — a Blackbox exporter scraped by Prometheus would restore the
   historical uptime%/incident-timeline view that Uptime Kuma provided (Gatus only covers current
   status + a short window).

**Grafana can't connect to Prometheus:**
- Both must be on the `promgraftail` network. Verify: `docker network inspect promgraftail | grep -A2 prometheus`
- Test from Grafana container: `docker exec grafana wget -qO- http://prometheus:9090/-/ready`

**Logs not appearing in Loki:**
- Check Alloy is running and its components are healthy: `docker logs alloy`, or the UI at
  `http://localhost:12345` (component graph shows per-source health).
- Container logs come from the Docker `loki` driver, not Alloy — if a container's logs are
  missing, check its `logging:` block, not Alloy.
- Check the Loki push endpoint: `curl http://localhost:3100/ready` (from host via port binding)

**Prometheus targets showing as down:**
- Navigate to `http://localhost:9070/targets` via SSH tunnel to see target status and error messages

**Alertmanager not sending alerts:**
- Check routing config in `alertmanager.yml`
- Test with `amtool` from inside the container: `docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml`
