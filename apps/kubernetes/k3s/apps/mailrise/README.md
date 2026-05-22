# Mailrise

SMTP-to-notifications gateway. Accepts SMTP email from services (Vaultwarden, Gatus, etc.) and forwards them to notification backends (ntfy, Discord, Slack, etc.).

## Overview

| | |
|---|---|
| **Image** | `yoryan/mailrise:latest` |
| **Domain** | `mailrise.hughboi.vip` |
| **SMTP Port** | 8025 |
| **Config** | ConfigMap (`/etc/mailrise.conf`) |

## How It Works

Services in the cluster point their SMTP config to `mailrise.mailrise.svc.cluster.local:8025` with no authentication and no TLS. Mailrise receives the email and forwards it to the notification URL(s) configured in `mailrise.conf`.

Internal cluster address: `mailrise.mailrise.svc.cluster.local:8025`

## Configuration

Edit [configmap.yaml](configmap.yaml) to add notification targets. See the [Mailrise docs](https://mailrise.xyz/configuration) for URL formats.

Common pattern — ntfy:
```yaml
configs:
  ntfy.alerts:
    urls:
      - ntfy://ntfy.ntfy.svc.cluster.local/alerts
```

After editing the ConfigMap, restart the deployment:
```bash
kubectl apply -f configmap.yaml
kubectl rollout restart deployment/mailrise -n mailrise
```

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml   # fill in notification targets first
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Wiring Up Other Services

Any service that needs email notifications should use:
- `SMTP_HOST`: `mailrise.mailrise.svc.cluster.local`
- `SMTP_PORT`: `8025`
- `SMTP_SECURITY`: `off` (no TLS between cluster services)
- `SMTP_FROM`: anything — Mailrise ignores the sender

The `ingressroute.yaml` exposes it externally if you need to send from outside the cluster. For cluster-internal use only, the Service alone is sufficient.

## Notes

- No persistent storage needed — config is entirely in the ConfigMap.
- Add `mailrise` to the Reflector annotation on the TLS certificate if you expose it externally.
