# ArgoCD App-of-Apps

`root-app.yaml` is the single Application you apply by hand during bootstrap. It watches this
directory and applies every Application/ApplicationSet here. Everything else is self-managing.

```
root-app  (wave 0, applied manually once)
 ├── metallb-config-app        (wave -3)  infra/metallb        IPAddressPool + L2Advertisement
 ├── longhorn-recurringjob-app (wave -1)  infra/longhorn       RecurringJobs (snapshot/backup)
 ├── system-upgrade-plans-app  (wave -1)  infra/system-upgrade Plans (k3s rolling upgrades)
 ├── adguard-app               (wave -1)  networking/adguard   AdGuard DNS
 ├── monitoring-app            (wave  1)  monitoring/          kube-prometheus-stack, Loki, Alloy
 └── apps-appset               (wave  1)  apps/*               one Application per app directory
```

## Manual bootstrap floor (NOT GitOps-managed — install before `root-app`)

These are the things ArgoCD, ingress, TLS, and storage themselves depend on. They're installed
once via Ansible/Helm during bootstrap (the "pragmatic floor"). DR = reinstall these, restore the
sealed-secrets master key, then apply `root-app` and the rest reconciles from Git.

| Floor component | Why it's manual |
|---|---|
| k3s + CNI + CoreDNS | The cluster itself (Ansible). |
| kube-vip | Fronts the API VIP that ArgoCD/kubectl talk to — must exist first. |
| MetalLB (controller) | Provides LoadBalancer IPs that Traefk/ArgoCD-ingress need. |
| Longhorn (controller) | Default StorageClass for every PVC. |
| cert-manager (controller) | Issues the wildcard TLS cert. |
| Traefik (controller) | Ingress for the ArgoCD UI itself. |
| sealed-secrets (controller) | Must decrypt SealedSecrets *before* ArgoCD syncs apps that contain them. Pairs with the manual master-key restore — see [`infra/sealed-secrets/`](../../infra/sealed-secrets/). |
| ArgoCD | The GitOps engine; bootstraps everything above this table's line. |

> The *controllers* are floor; their **config CRs are GitOps-managed** (e.g. MetalLB's pool,
> cert-manager's Issuer/Certificate). That's the split this directory implements.

## Sync-wave scheme

Lower waves apply first. Infra/networking config is negative so it precedes apps (wave 1).

| Wave | Contents | Rationale |
|---|---|---|
| -3 | MetalLB pool; (planned) cert-manager Issuer + cloudflare sealed secret; reflector | LB IPs + TLS issuance must be ready before services/certs. |
| -2 | (planned) cert-manager Certificate; Traefik middlewares/headers; CrowdSec | TLS cert + edge security before apps are exposed. |
| -1 | AdGuard; Longhorn RecurringJobs; system-upgrade Plans; (planned) velero, tailscale | Cluster services that depend only on the floor. |
|  1 | monitoring + all user apps | Everything user-facing, last. |

## Implemented here now

- `metallb-config-app` — IPAddressPool (`10.10.30.60-99`) + L2Advertisement.
- `longhorn-recurringjob-app` — hourly snapshot + daily/weekly backup jobs (backups need a target, Phase 3).
- `system-upgrade-plans-app` — k3s server/agent upgrade Plans.
- `adguard-app` — AdGuard DNS (Phase-2 hardening pending: pin image, pin LB IP `.65`, probes).
- `reflector-app` — emberstack/reflector 10.0.46 (Helm multi-source) — mirrors the wildcard TLS secret.
- `crowdsec-app` — crowdsec/crowdsec 0.24.0 (Helm multi-source) — edge security (LAPI + agent).

## Follow-ups (not yet wired — each needs a decision or a secret)

1. **Helm-based components**: reflector + CrowdSec are now done (multi-source, pinned `10.0.46` / `0.24.0`).
   **Velero** and **Tailscale operator** remain — they also need their secrets/targets first (Velero S3
   creds + bucket → Phase 3; Tailscale OAuth client sealed) before they can sync healthily.
2. **cert-manager Issuer + Certificate** and **Traefik dashboard** → blocked on sealing the
   `cloudflare-token-secret` (cert-manager ns) and the dashboard basic-auth secret. Author once
   Sealed Secrets is live (Phase 1.1).
3. **Velero / Tailscale** → also need their secrets sealed (S3 creds; OAuth client) and Velero
   needs its S3 target to exist (Phase 3).
4. **network-policies** → applied per-app via each app's `networkpolicy.yaml` (the GitOps-preferred
   pattern in [`networking/network-policies/`](../../networking/network-policies/)), not as a
   directory Application — the templates carry no namespace.
5. **Pin LoadBalancer IPs** — AdGuard/Traefik Services don't set `loadBalancerIP`, so their
   addresses can drift on redeploy (bad for DNS). Pin `metallb.io/loadBalancerIPs`.
