# Monitoring Stack (k3s)

Prometheus · Grafana · Loki · Alloy

**Full architecture and runbook:** `docs/8-k3s/Monitoring.md`

---

## Summary

k3s is the target monitoring platform. One Grafana (`grafana.hughboi.vip`) as single pane of glass, pulling from:
- k3s Prometheus — k3s cluster, dock-prod host, bind9, CrowdSec, Unifi
- k3s Loki — all logs (k3s pods + dock-prod logs shipped by Alloy)
- dock-prod InfluxDB — SNMP + Proxmox push metrics (no k8s equivalent)

dock-prod Grafana/Prometheus/Promtail are retired once k3s monitoring is live.

---

## Directory Layout

```
monitoring/
├── namespace.yaml
├── alertmanager-rules/      # custom PrometheusRule CRDs
├── kube-prometheus-stack/
│   ├── values.yaml          # Prometheus + Grafana + AlertManager config
│   ├── grafana-ingressroute.yaml
│   └── prometheus-ingressroute.yaml   # exposes prometheus.hughboi.vip
├── loki/
│   └── values.yaml
└── alloy/
    ├── values.yaml
    └── config.alloy         # pod log collection pipeline
```

---

## Quick Deploy

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl apply -f namespace.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f kube-prometheus-stack/values.yaml \
  --set alertmanager.config.receivers[0].discord_configs[0].webhook_url=<webhook> \
  --set alertmanager.config.receivers[1].email_configs[0].to=<email>

kubectl apply -f kube-prometheus-stack/grafana-ingressroute.yaml
kubectl apply -f kube-prometheus-stack/prometheus-ingressroute.yaml

helm upgrade --install loki grafana/loki -n monitoring -f loki/values.yaml

helm upgrade --install alloy grafana/alloy -n monitoring \
  --set-file alloy.configMap.content=alloy/config.alloy \
  -f alloy/values.yaml
```

## Notes

- **Secrets** — Discord webhook and email are intentionally blank in `values.yaml`. Pass at deploy time via `--set`.
- **k3s control plane rules** are disabled (`etcd`, `kubeControllerManager`, `kubeProxy`, `kubeScheduler`) — k3s runs these in-process and doesn't expose metric endpoints.
- **Helm release name matters** — Grafana service is `kube-prometheus-stack-grafana`. If you change the release name, update the IngressRoute service ref.
- **Prerequisites** — Longhorn, cert-manager + `letsencrypt-production` ClusterIssuer, Traefik with `traefik-external` ingressClass, Reflector (reflects `hughboi-tls` into `monitoring` namespace).
