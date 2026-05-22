# prometheus-pve-exporter

Exports Proxmox VE metrics (CPU, memory, disk, VM/CT status, storage pool usage) to Prometheus. Replaces the Docker stack's InfluxDB + Telegraf Proxmox push path.

## Why

The Docker stack uses Telegraf with `inputs.proxmox` → InfluxDB. That path requires a separate InfluxDB instance and doesn't integrate with the kube-prometheus-stack dashboards. This exporter runs in-cluster, scrapes Proxmox via its API, and feeds directly into Prometheus.

## How it works

The exporter runs as a single pod with no persistent state. Prometheus scrapes it at `/pve?target=<proxmox-host>` — the exporter proxies the request to the Proxmox API and returns metrics in Prometheus format. The ServiceMonitor in `servicemonitor.yaml` configures three scrape jobs (one per Proxmox node) with relabeling so each node appears as a distinct `instance` label.

## Prerequisites

1. Create a Proxmox API token with `PVEAuditor` (read-only) role:
   ```
   Proxmox UI → Datacenter → Permissions → API Tokens → Add
   User: prometheus@pve
   Token ID: prometheus
   Privilege Separation: unchecked
   
   Datacenter → Permissions → Add → API Token Permission
   Path: /
   Token: prometheus@pve!prometheus
   Role: PVEAuditor
   ```

2. Create the secret imperatively:
   ```bash
   kubectl create secret generic pve-exporter-env \
     --namespace prometheus-pve-exporter \
     --from-literal=PVE_USER=prometheus@pve \
     --from-literal=PVE_TOKEN_NAME=prometheus \
     --from-literal=PVE_PASSWORD=<the-token-secret-shown-once-at-creation> \
     --from-literal=PVE_VERIFY_SSL=false
   ```

3. Update `servicemonitor.yaml` → replace the `target` list with your actual Proxmox node hostnames or IPs.

## Deploy

```bash
kubectl apply -f apps/kubernetes/k3s/apps/prometheus-pve-exporter/namespace.yaml
kubectl apply -f apps/kubernetes/k3s/apps/prometheus-pve-exporter/
```

ArgoCD will auto-sync this once the secret exists.

## Verify

```bash
# Check exporter is running
kubectl get pods -n prometheus-pve-exporter

# Test a scrape manually (replace with your Proxmox IP)
kubectl port-forward -n prometheus-pve-exporter svc/prometheus-pve-exporter 9221:9221 &
curl "http://localhost:9221/pve?target=10.10.30.X"

# Check Prometheus sees it
# Prometheus UI → Status → Targets → filter "pve"
```

## Grafana Dashboard

Import dashboard ID **10347** (Proxmox via Prometheus) from grafana.com.

Or use the official dashboard from the exporter project:
```
https://github.com/prometheus-pve/prometheus-pve-exporter/blob/main/grafana/dashboard.json
```

## Decommissioning Docker InfluxDB

Once this exporter is verified working in Prometheus/Grafana:
1. Remove the Telegraf `inputs.proxmox` config from the Docker stack
2. Export any historical data from InfluxDB you want to retain (it won't migrate automatically)
3. Shut down InfluxDB + Telegraf Docker containers
