# Promgraftail — Observability Stack

The central metrics and logging stack for the homelab. All observability runs here.

See [loki/README.md](loki/README.md) for detailed Loki + Promtail setup.

## Services

| Container | Image | URL | Purpose |
|---|---|---|---|
| `grafana` | `grafana/grafana` | https://grafana.hughboi.cc | Dashboards and visualization |
| `loki` | `grafana/loki` | https://loki.hughboi.cc | Log aggregation and query |
| `prometheus` | `prom/prometheus` | `127.0.0.1:9070` (localhost only) | Metrics scraping and alerting |
| `alertmanager` | `quay.io/prometheus/alertmanager` | `127.0.0.1:9093` (localhost only) | Alert routing |
| `promtail` | `grafana/promtail` | — (no UI) | Log shipping to Loki |
| `influxdb` | `influxdb` | https://influxdb.hughboi.cc | Time-series DB for Telegraf/SNMP metrics |
| `telegraf` | `telegraf` | — (no UI) | SNMP + host metrics collector → InfluxDB |
| `alloy` | `grafana/alloy` | https://alloy.hughboi.cc | Grafana Alloy agent (OTel collector) |

All services are on the `promgraftail` internal Docker network. Grafana, Loki, InfluxDB, and Alloy also join the `proxy` network for Traefik routing.

## Network Layout

```
Internet → Traefik → [grafana, loki, influxdb, alloy]
                            ↕
                    promgraftail network
                  [prometheus, alertmanager, promtail, telegraf]
                            ↕
              Other stacks (unifi, promgraftail → shared network)
```

Prometheus and alertmanager are **not** exposed via Traefik. Access them via SSH tunnel if needed.

## Config Files (all in `/home/hughboi/code/promgraftail/`)

| File | Service | Purpose |
|---|---|---|
| `prometheus/prometheus.yml` | prometheus | Scrape configs and alerting rules pointer |
| `prometheus/alert-rules.yml` | prometheus | Alert rule definitions |
| `prometheus/alertmanager.yml` | alertmanager | Alert routing (receivers, routes) |
| `loki/config.yaml` | loki | Loki storage and retention config |
| `promtail/config.yaml` | promtail | Log scrape targets and Loki push config |
| `telegraf/telegraf.conf` | telegraf | SNMP and host input configs |
| `alloy/config.alloy` | alloy | Alloy pipeline config (OTel format) |

All config files are mounted `:ro` — restart the service after any config change.

## Grafana

**User:** admin (set password on first login)
**Grafana UID:** 472 — the data directory must be owned by 472:

```sh
sudo chown -R 472:472 /home/hughboi/data/grafana
```

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
- `cadvisor` — Docker container metrics (if cadvisor is running)

Alertmanager is configured in `prometheus.yml`:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

## Promtail

Scrapes:
- `/var/log` on the host (all syslog, auth.log, etc.)
- Docker container logs via `docker.sock`
- Unbound log at `/home/hughboi/adguard/unbound/unbound.log`

Port `1514` is open for receiving syslog from network devices (routers, switches, firewalls).

## Telegraf

Runs as `telegraf:988` (the telegraf group on the host, needed for docker.sock access). Collects:
- Host system metrics (CPU, memory, disk, network) via host filesystem mounts
- SNMP metrics (configured in `telegraf.conf`) → pushed to InfluxDB

## InfluxDB

- Web UI on https://influxdb.hughboi.cc
- Also accessible on `127.0.0.1:8086` from the host
- Port `8089/udp` is for the InfluxDB line protocol UDP listener

Initial setup is done through the web UI — creates the org, bucket, and admin token on first run. Store the admin token in `.env` after generation.

## Alloy

Grafana Alloy is the next-gen OTel collector replacing Promtail. It can ingest logs, metrics, and traces. The web UI is at https://alloy.hughboi.cc (port 3100 via Traefik) and the agent listen port is `127.0.0.1:12345`.

## Upgrade Notes

- Grafana: back up `/home/hughboi/data/grafana` before upgrading — contains dashboards, data source configs, users.
- Loki: back up `/home/hughboi/data/loki/data` — contains the log chunks and index.
- InfluxDB: back up `/home/hughboi/data/influxdb`.
- Prometheus, Alertmanager, Promtail, Telegraf: stateless config — no data to back up separately.

## Troubleshooting

**⚠️ Known issue (unresolved):** `promtail` was observed crash-looping (`Restarting`) on
dock-prod during the SOPS migration session, unrelated to anything changed that night — root
cause not yet investigated. This stack is deliberately **not yet SOPS-migrated**, both because of
this crash loop and because Loki here is a dependency for every other service's
`logging: driver: loki` — a broken Loki doesn't just lose this stack's own logs, it silently
drops shipped logs fleet-wide. Diagnose and fix the crash loop (`docker logs promtail`) before
attempting any path/secrets migration on this stack.

**⚠️ Bigger finding (full-repo audit, confirmed on the live host):** every bind-mount source path
in `compose.yaml` claims `/home/hughboi/code/promgraftail/...` — **this directory doesn't exist
on dock-prod at all.** The actual live containers are mounted from a third, different path
entirely: `/home/hughboi/promgraftail/<service>/...` (confirmed directly, e.g.
`docker inspect loki --format '{{json .Mounts}}'` shows
`/home/hughboi/promgraftail/loki/config/config.yaml`, not the repo's claimed path). This means
`compose.yaml` has not actually driven a real deploy of this stack in some time — it's an
aspirational/hand-edited "should be" file, not what's running. Corroborating evidence: the live
`grafana` and `prometheus` containers are running `:main`/`:latest` respectively, not the pinned
`13.0.1`/`v3.11.3` versions `compose.yaml` specifies.

The repo's tracked config files (`loki/config.yaml`, `prometheus/*.yml`, `telegraf/telegraf.conf`,
`promtail/config.yaml`) are themselves **stale relative to the live host versions**, not the other
way around — e.g. the repo's `promtail/config.yaml` uses old `dock-prod_*` job-name labels (the
live version uses `ubnt-prod_*`, suggesting a hostname rename that was never synced back) and is
missing two entire scrape jobs the live config has: `unbound_logs` and `bind9` (syslog receiver).

**Before touching this stack's mounts/paths at all**, the full-repo audit (July 2026) recommends:
1. Diff every one of the 6 services' actual live config (via `docker inspect <name> --format
   '{{json .Mounts}}'` to find the true `Source:`, then `cat`/`diff` its contents) against the
   repo's tracked copy — assume the **live host is the source of truth**, not the repo, given the
   evidence above.
2. Decide the target convention once, for the whole stack: `/home/hughboi/homelab/apps/docker/promgraftail/...`
   (the convention every other SOPS-migrated service now uses) is the natural choice, but this is
   a real decision, not a given.
3. Update the repo's tracked config files from the live (correct) versions where they've drifted,
   *then* update `compose.yaml`'s mounts, *then* redeploy and verify — the same careful
   diff-first discipline used for every other migration this session (see the `pocket-id`
   incident in this repo's history for why skipping this step is dangerous).
4. Re-pin `grafana`/`prometheus` to explicit versions matching what's actually intended to run,
   not what happens to be cached on the host right now.
5. Add long-term uptime/history monitoring via this stack (e.g. Blackbox exporter scraped by
   Prometheus, visualized in Grafana) — Uptime Kuma was sunset 2026-07-17 in favor of Gatus, but
   Gatus only covers current status + a short window, not the historical uptime %/incident-timeline
   view Kuma provided. This is the intended replacement for that gap, not Gatus itself.

This is intentionally scoped as one combined future session (crash-loop fix + path/convention
migration + SOPS migration + optional node_exporter addition for host metrics, plus the Blackbox
exporter addition above), not a quick fix — see the main homelab todo list.

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
