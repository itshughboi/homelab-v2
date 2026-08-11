# Promtail (sunset)

**Sunset:** 2026-08 — replaced by **Grafana Alloy**.
**Live replacement:** `alloy` service in [../../promgraftail/compose.yaml](../../promgraftail/compose.yaml), config in [../../promgraftail/alloy/config.alloy](../../promgraftail/alloy/config.alloy).

## Why it was sunset

Promtail is end-of-life upstream — Grafana has consolidated logs/metrics/traces
collection into [Alloy](https://grafana.com/docs/alloy/). Rather than keep running
an EOL agent, the log collection was ported 1:1 to Alloy.

## What it used to do

The scrape jobs (see [config.yaml](config.yaml)):

| Job | Purpose | Ported to Alloy? |
|---|---|---|
| `dock-prod_varlogs` | tail dock-prod `/var/log/*log` | ✅ `loki.source.file "varlogs"` |
| `pve-srv-1..4_system` | labels only; all pointed at the same local `/var/log` (promtail didn't remote-read those hosts) | ➖ collapsed into the single varlogs job |
| `bind9` | syslog receiver on `:1514` (published `1541:1514`) | ✅ `loki.source.syslog "bind9"` |
| `adguard-queries` | AdGuard query log JSON → Loki (client/blocked/qtype labels) | ✅ `loki.process "adguard"` |
| docker logs (`platform=docker`) | scraped container logs via docker.sock | ❌ dropped — **redundant**: every container already ships stdout via the Docker `loki` logging driver |

## Resurrecting (reference only)

This `compose.yaml` is the last-known-good standalone definition. It is not
deployed. If you ever need it back, stop Alloy's bind9 syslog listener first so
both don't bind host port `1541`.
