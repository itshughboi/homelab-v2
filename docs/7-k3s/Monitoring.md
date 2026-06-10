# Monitoring

## Architecture

One Grafana. Everything feeds it.

```
k3s Grafana (grafana.hughboi.vip)        ← single pane of glass
  ├── data source: k3s Prometheus         → k3s cluster, dock-prod host, bind9, CrowdSec, Unifi
  ├── data source: k3s Loki               → k3s pod logs + dock-prod logs (shipped by Alloy)
  └── data source: dock-prod InfluxDB     → SNMP + Proxmox native push metrics

dock-prod Alloy                           ← log shipper; replaces Promtail
  └── ships logs → k3s Loki (loki-gateway.monitoring.svc / external IngressRoute)

dock-prod Telegraf → dock-prod InfluxDB   ← stays; SNMP + Proxmox push have no k8s equivalent
```

**What's retired once k3s is live:**
- `grafana.hughboi.cc` — Docker Grafana (replaced by `grafana.hughboi.vip`)
- dock-prod Prometheus (`localhost:9070`) — barely used, only scraped 2 targets
- dock-prod Promtail — replaced by Alloy

---

## k3s Stack (target)

Deployed in the `monitoring` namespace. Source: `apps/kubernetes/k3s/monitoring/`

| Component | Purpose |
|-----------|---------|
| kube-prometheus-stack | Prometheus + Grafana + AlertManager + node-exporter + kube-state-metrics |
| Loki | Log storage (single binary, Longhorn PVC) |
| Alloy | Pod log collection + k8s events → Loki |

### Deploy order

```sh
# 1. Namespace
kubectl apply -f apps/kubernetes/k3s/monitoring/namespace.yaml

# 2. Reflect wildcard TLS cert into monitoring namespace
kubectl apply -f apps/kubernetes/k3s/networking/traefik/helm/traefik/cert-manager/certificates/production/hughboi-production.yaml
kubectl get secret hughboi-tls -n monitoring   # wait for it

# 3. kube-prometheus-stack
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f apps/kubernetes/k3s/monitoring/kube-prometheus-stack/values.yaml \
  --set alertmanager.config.receivers[0].discord_configs[0].webhook_url=<discord-webhook-url> \
  --set alertmanager.config.receivers[1].email_configs[0].to=<email>

kubectl apply -f apps/kubernetes/k3s/monitoring/kube-prometheus-stack/grafana-ingressroute.yaml
kubectl apply -f apps/kubernetes/k3s/monitoring/kube-prometheus-stack/prometheus-ingressroute.yaml

# 4. Loki
helm upgrade --install loki grafana/loki \
  -n monitoring \
  -f apps/kubernetes/k3s/monitoring/loki/values.yaml

# 5. Alloy
helm upgrade --install alloy grafana/alloy \
  -n monitoring \
  --set-file alloy.configMap.content=apps/kubernetes/k3s/monitoring/alloy/config.alloy \
  -f apps/kubernetes/k3s/monitoring/alloy/values.yaml
```

**Grafana:** `https://grafana.hughboi.vip` — default credentials `admin/prom-operator`, change immediately.

---

## Scrape Targets (k3s Prometheus)

All configured in `apps/kubernetes/k3s/monitoring/kube-prometheus-stack/values.yaml` → `additionalScrapeConfigs`:

| Job | Target | Notes |
|-----|--------|-------|
| k3s nodes | node-exporter DaemonSet | automatic via kube-prometheus-stack |
| kube-state-metrics | in-cluster | automatic |
| crowdsec | `crowdsec-service.crowdsec.svc:6060` | in-cluster |
| unifipoller | `unifi-poller.unifi.svc:9130` | in-cluster |
| bind9 | `10.10.10.8:9119` | Athena — run bind-exporter playbook first |
| dock-prod host | `10.10.10.10:9100` | add node_exporter to dock-prod (see below) |

### Add node_exporter to dock-prod

So k3s Prometheus can scrape the Docker host:

```sh
docker run -d --name node-exporter --restart unless-stopped \
  --net="host" --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter:latest \
  --path.rootfs=/host
```

Then add to `values.yaml` additionalScrapeConfigs:
```yaml
- job_name: dock-prod
  static_configs:
    - targets: ['10.10.10.10:9100']
```

---

## dock-prod Stack (legacy → retained components)

Source: `apps/docker/promgraftail/` — **read-only reference, do not modify live files here.**

| Component | Keep? | Reason |
|-----------|-------|--------|
| Grafana | Retire | Replaced by k3s Grafana |
| Prometheus | Retire | k3s Prometheus covers everything |
| Promtail | Retire | Replaced by Alloy |
| Loki | Retire | Replaced by k3s Loki |
| AlertManager | Retire | Replaced by k3s AlertManager |
| **Alloy** | **Keep** | Ships dock-prod logs to k3s Loki |
| **Telegraf** | **Keep** | SNMP + Proxmox metrics (no k8s push equivalent) |
| **InfluxDB** | **Keep** | Receives Telegraf + Proxmox native push; add as Grafana data source |

### Add InfluxDB to k3s Grafana

In Grafana UI → Connections → Data Sources → Add → InfluxDB:
- URL: `https://influxdb.hughboi.cc`
- Query language: Flux
- Org/Token: from Vaultwarden

---

## Alerts

AlertManager routes → Discord + email (mailrise). Config in `values.yaml` — credentials passed at deploy time via `--set`, never committed.

Custom alert rules: `apps/kubernetes/k3s/monitoring/alertmanager-rules/`

---

## Dead-man's switch

> [!WARNING] Status: designed, **not yet implemented**
> The Watchdog route + healthchecks.io receiver below are a proposal — they are **not** in
> `kube-prometheus-stack/values.yaml` yet (its Alertmanager receivers are still blank). Wire this
> up as part of monitoring hardening before relying on it.

The gap normal alerting can't cover: **if Prometheus/Alertmanager themselves die, no alert fires
— you just get silence.** A dead-man's switch inverts that: something *outside* the stack expects
a steady heartbeat and alerts you when it **stops**.

> [!IMPORTANT] It's PUSH, not pull — so "nothing is publicly accessible" doesn't matter
> The homelab pushes an *outbound* heartbeat to the external service every few minutes. If the
> heartbeat stops (monitoring/cluster/power dead), the external service notices the silence and
> emails/texts you. Nothing inbound, no public exposure — just outbound HTTPS, which you have.

**How (kube-prometheus-stack makes this trivial):** it ships a `Watchdog` alert that is *always
firing* by design. Route that one alert to a **[healthchecks.io](https://healthchecks.io)** ping
URL via an Alertmanager webhook receiver:

```yaml
# alertmanager config (values.yaml) — sketch
route:
  routes:
    - matchers: [ 'alertname="Watchdog"' ]
      receiver: deadmanswitch
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 50s          # ping well within the healthchecks.io period
receivers:
  - name: deadmanswitch
    webhook_configs:
      - url: https://hc-ping.com/<your-check-uuid>   # store via --set, not committed
        send_resolved: false
```

Set the healthchecks.io check's **period** to ~2× the `repeat_interval` (e.g. 2 min) with a grace
window. While the cluster is healthy, the Watchdog pings keep it green; if the cluster, Prometheus,
Alertmanager, networking, or power dies, the pings stop → healthchecks.io alerts you **out of band**.

> [!NOTE] Why external beats a self-hosted watcher
> A gatus/uptime-kuma on Athena can watch *services*, but it's **not** a true dead-man for the
> homelab — Athena and dock-prod are both on pve-srv-1, and any on-prem watcher dies with a
> site-wide power/network loss. The external push survives total loss. If you want to avoid a SaaS
> dependency, run the *receiver* on a cheap external VPS joined to your tailnet — but that's more
> infra for the same outcome. **healthchecks.io free tier is the pragmatic choice.**

---

## Dashboards

Import from grafana.com after setup:

| ID | Dashboard |
|----|-----------|
| 1860 | Node Exporter Full |
| 11315 | UniFi Poller |
| 1666 | Bind9 (bind_exporter) |
| 13639 | Loki Logs |
| 15520 | Longhorn |

---

## Verify

```sh
kubectl get pods -n monitoring          # all Running
curl -I https://grafana.hughboi.vip     # 200
curl -I https://prometheus.hughboi.vip  # 200 (internal use by dock-prod Grafana if needed)

# Loki receiving logs (give Alloy ~30s to start)
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=20
```
