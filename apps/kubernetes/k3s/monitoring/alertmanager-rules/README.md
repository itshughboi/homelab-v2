# Alertmanager Rules

Custom `PrometheusRule` resources picked up by the kube-prometheus-stack Prometheus operator.

## Rule Groups

| Group | What It Covers |
|-------|---------------|
| `nodes` | Node exporter down, CPU >90%, disk >85%/95%, memory >90% |
| `pods` | Crash-looping containers, pods not ready, deployment replica mismatches |
| `certificates` | cert-manager certs expiring <14d (warning) / <3d (critical), non-ready certs |
| `longhorn` | Volume >90% full, degraded/faulted volumes, node storage >85% |
| `k3s` | PVCs stuck pending, failed Jobs |

## Routing Alerts to Mailrise/Ntfy

Configure Alertmanager in the kube-prometheus-stack values to route to ntfy:

```yaml
# apps/kubernetes/k3s/monitoring/kube-prometheus-stack/values.yaml
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: ntfy
      routes:
        - match:
            severity: critical
          receiver: ntfy-critical
    receivers:
      - name: ntfy
        webhook_configs:
          - url: http://ntfy.ntfy.svc.cluster.local/homelab-alerts
            send_resolved: true
      - name: ntfy-critical
        webhook_configs:
          - url: http://ntfy.ntfy.svc.cluster.local/homelab-critical
            send_resolved: true
```

Ntfy topics can have different priorities — set `homelab-critical` with priority 5 (urgent) in ntfy access control.

## Deploying

```bash
kubectl apply -f homelab-rules.yaml
# Verify Prometheus picked them up
kubectl get prometheusrule -n monitoring
```

The rule file has `release: kube-prometheus-stack` label which matches the ruleSelector kube-prometheus-stack configures by default.

## Silencing an Alert

```bash
# Via amtool (if you have it) or the Alertmanager UI at the Grafana /alertmanager proxy
amtool silence add alertname=NodeDiskUsageHigh instance=k3s-longhorn-1 --duration=2h --comment "expanding disk"
```
