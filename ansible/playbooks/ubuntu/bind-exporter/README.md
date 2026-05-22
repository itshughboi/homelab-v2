# bind-exporter

Deploys [bind_exporter](https://github.com/prometheus-community/bind_exporter) on Athena so Prometheus can scrape Bind9 DNS metrics.

## What it does

1. Enables the Bind9 XML statistics channel on `127.0.0.1:8053`
2. Downloads and installs `bind_exporter` binary to `/usr/local/bin/`
3. Runs it as a systemd service on port `9119`
4. Opens UFW to allow Prometheus scraping from the k3s VLAN (`10.10.30.0/24`)

Metrics include: queries per second, cache hit rate, record types served, NXDOMAIN rate, zone transfer activity.

## Run

```sh
cd ansible/playbooks/ubuntu/bind-exporter
ansible-playbook -i inventory.ini main.yaml
```

## After running

**Prometheus scrape** is already wired in `apps/kubernetes/k3s/monitoring/kube-prometheus-stack/values.yaml`:
```yaml
- job_name: bind9
  static_configs:
    - targets: ['10.10.10.8:9119']
```

**Grafana dashboard**: Import ID `1666` from grafana.com — works out of the box with bind_exporter metrics.

## Targets

| Host | IP | Role |
|---|---|---|
| athena | 10.10.10.8 | Runs Bind9 + bind_exporter |

## Notes

- Bind9 must be running (`named` service) — the playbook fails if named can't start the stats channel
- Restart is only needed for Bind9 config change (`named-checkconf` runs before reload)
- The `statistics-channels` block is inserted via `blockinfile` — idempotent, safe to re-run
- `bind_exporter_version` in `vars` — bump this to upgrade
