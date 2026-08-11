# cAdvisor (sunset)

**Sunset:** 2026-08 — not deployed.

cAdvisor exports per-container CPU/mem/net/disk metrics to Prometheus. It was kept
as a standalone (never wired into the running promgraftail stack). Container-level
metrics are otherwise covered by:
- **Telegraf** (docker input → InfluxDB) for the "InfluxDB - Telegraf Docker" dashboard
- the option to enable cAdvisor via **Alloy** (`prometheus.exporter.cadvisor`, present
  but commented out in `apps/docker/promgraftail/alloy/config.alloy`)

Kept here for reference. To resurrect: move back into the promgraftail stack (or
enable the Alloy cadvisor block) and add a Prometheus scrape job for `:8073`.
