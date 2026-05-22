# Monitoring Stack (k3s)

Prometheus · Grafana · Loki · Alloy

## Cross-environment monitoring

This is one of two monitoring stacks. The other lives in `apps/docker/promgraftail` on dock-prod.

```
dock-prod Grafana (grafana.hughboi.cc)  ←── PRIMARY user-facing dashboard
  ├── data source: local Prometheus      → dock-prod host + Docker container metrics
  ├── data source: local Loki            → dock-prod system + Docker logs
  ├── data source: k3s Prometheus *      → k3s cluster metrics (pods, nodes, PVE, bind9)
  └── data source: k3s Loki *            → k3s pod logs and Kubernetes events

k3s Prometheus (prometheus.hughboi.vip) ←── in-cluster scraper, also reachable externally
  ├── node-exporter DaemonSet            → all k3s node host metrics
  ├── kube-state-metrics                 → pod/deployment/PVC state
  ├── CrowdSec, UniFi, PVE exporter     → external service metrics
  └── bind9 on Athena (10.10.10.8:9119) → DNS metrics via bind_exporter

dock-prod Prometheus (localhost:9070)   ←── watchdog: if k3s goes down, this still runs
  └── alerts if k3s Prometheus unreachable
```

`*` = add k3s Prometheus and k3s Loki as data sources in **dock-prod Grafana**:
- **k3s Prometheus**: `https://prometheus.hughboi.vip` — IngressRoute in `kube-prometheus-stack/prometheus-ingressroute.yaml`
- **k3s Loki**: `http://loki-gateway.monitoring.svc.cluster.local` (in-cluster only; expose via IngressRoute if needed from Grafana outside k3s)

**Adding node_exporter to dock-prod** (optional, so k3s Prometheus can scrape it):
```sh
# On dock-prod, run node_exporter on port 9100
docker run -d --name node-exporter --restart unless-stopped \
  --net="host" --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter:latest \
  --path.rootfs=/host
# Then add to kube-prometheus-stack/values.yaml additionalScrapeConfigs:
#   - job_name: dock-prod
#     static_configs:
#       - targets: ['10.10.10.10:9100']
```

## Architecture

| Component | Role |
|-----------|------|
| kube-prometheus-stack | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics |
| Loki | Log storage (single binary, Longhorn PVC) |
| Alloy | Pod log collection + k8s events → Loki via k8s API |

Alloy replaces Promtail and Grafana Agent. It discovers pods via the k8s API and ships logs directly to Loki — no filesystem mounts or per-node DaemonSet needed for log collection. Metrics are fully covered by kube-prometheus-stack (node-exporter DaemonSet, kube-state-metrics).

## Prerequisites

- Longhorn installed and set as a StorageClass
- cert-manager + `letsencrypt-production` ClusterIssuer
- Traefik with `traefik-external` ingressClass
- Reflector installed (reflects `hughboi-tls` secret from `traefik` → `monitoring` namespace)

## Helm Repos

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## Deploy Order

### 1. Namespace

```bash
kubectl apply -f namespace.yaml
```

### 2. TLS — reflect wildcard cert into monitoring namespace

Apply the updated certificate (adds Reflector annotations so `hughboi-tls` is mirrored automatically):

```bash
kubectl apply -f ../traefik/helm/traefik/cert-manager/certificates/production/hughboi-production.yaml
```

Verify the secret appears in `monitoring` before proceeding:

```bash
kubectl get secret hughboi-tls -n monitoring
```

### 3. kube-prometheus-stack

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kube-prometheus-stack/values.yaml \
  --set alertmanager.config.receivers[0].discord_configs[0].webhook_url=<discord-webhook-url> \
  --set alertmanager.config.receivers[1].email_configs[0].to=<email>

kubectl apply -f kube-prometheus-stack/grafana-ingressroute.yaml
```

Grafana will be available at `https://grafana.hughboi.vip`. Default credentials are `admin/prom-operator` — change immediately.

### 4. Loki

```bash
helm upgrade --install loki grafana/loki \
  -n monitoring \
  -f loki/values.yaml
```

Loki is provisioned as a Grafana datasource automatically via `additionalDataSources` in the kube-prometheus-stack values. No manual Grafana setup needed.

### 5. Alloy

```bash
helm upgrade --install alloy grafana/alloy \
  -n monitoring \
  --set-file alloy.configMap.content=alloy/config.alloy \
  -f alloy/values.yaml
```

## Verify

```bash
# All pods running
kubectl get pods -n monitoring

# Grafana reachable
curl -I https://grafana.hughboi.vip

# Loki receiving logs (give Alloy ~30s to start shipping)
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=20
```

## What's not here (and why)

The Docker monitoring stack (`apps/docker/promgraftail`) includes **Telegraf** and **InfluxDB** which have no equivalent in this k8s stack — they're intentionally omitted:

| Docker tool | Replaced by |
|-------------|-------------|
| Telegraf (Docker container metrics) | Alloy's built-in cadvisor exporter + kube-prometheus-stack node-exporter |
| InfluxDB (Proxmox native push target) | No k8s equivalent yet — Proxmox still pushes to the Docker InfluxDB instance |

Telegraf and InfluxDB remain running in the Docker stack and are still the source of truth for Proxmox metrics. A future improvement would be to replace InfluxDB with `prometheus-pve-exporter`, which queries the Proxmox REST API and exposes metrics in Prometheus format — eliminating the push dependency entirely.

## Notes

- **Scrape targets** in `kube-prometheus-stack/values.yaml` include your existing Docker-side targets (`crowdsec` and `unifipoller` at `10.10.10.10`). Update the IP if your Docker host address differs on the k8s network.
- **Helm release name matters** — the Grafana service name in `grafana-ingressroute.yaml` is `kube-prometheus-stack-grafana`, derived from the release name `kube-prometheus-stack`. If you use a different release name, update the service name in the IngressRoute.
- **k3s control plane rules** are disabled in `defaultRules` (etcd, controller-manager, scheduler, kube-proxy) — k3s runs these in-process and doesn't expose their metrics endpoints.
- **Alertmanager secrets** — Discord webhook URL and email target are intentionally left blank in `values.yaml`. Pass them at deploy time via `--set` to avoid committing credentials.
