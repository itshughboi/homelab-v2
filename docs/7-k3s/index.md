# 7. k3s

HA k3s cluster across 9 nodes on pve-srv-2, 3, 4. ArgoCD watches Gitea and applies everything declaratively — no manual `kubectl apply` for ongoing operations.

---

## Cluster Layout

3 control plane nodes (tainted NoSchedule, etcd embedded) + 3 workers + 3 dedicated Longhorn storage nodes.

| VM | Host | VLAN | IP | Role |
| --- | --- | --- | --- | --- |
| k3s-master-1 | pve-srv-2 | 30 | 10.10.30.1 | Control plane |
| k3s-master-2 | pve-srv-3 | 30 | 10.10.30.2 | Control plane |
| k3s-master-3 | pve-srv-4 | 30 | 10.10.30.3 | Control plane |
| k3s-worker-1 | pve-srv-2 | 30/40 | 10.10.30.11 | Workloads |
| k3s-worker-2 | pve-srv-3 | 30/40 | 10.10.30.12 | Workloads |
| k3s-worker-3 | pve-srv-4 | 30/40 | 10.10.30.13 | Workloads |
| k3s-longhorn-1 | pve-srv-2 | 30/40 | 10.10.30.51 | Dedicated Longhorn storage |
| k3s-longhorn-2 | pve-srv-3 | 30/40 | 10.10.30.52 | Dedicated Longhorn storage |
| k3s-longhorn-3 | pve-srv-4 | 30/40 | 10.10.30.53 | Dedicated Longhorn storage |

Workers and Longhorn nodes are dual-homed (VLAN 30 + VLAN 40) so storage traffic — replica sync
between Longhorn nodes and volume access from workers — uses the storage VLAN, not the workload
VLAN. VM sizing (workers 50 GB, Longhorn nodes 200 GB) is in the
[Terraform spec](../2-proxmox/provisioning/README.md#vm-spec-table).

### Virtual IPs (MetalLB)

| VIP | IP | Purpose |
| --- | --- | --- |
| k3s-api-vip | 10.10.30.30 | kube-vip HA control plane — all `kubectl` points here |
| k3s-longhorn-vip | 10.10.30.50 | Longhorn UI |
| traefik-vip | 10.10.30.65 | k3s ingress (MetalLB) |
| adguard-vip | 10.10.30.69 | k3s DNS (MetalLB) |
| MetalLB pool | 10.10.30.60–99 | Available for LoadBalancer services |

---

## Install / Reinstall

```sh
# 1. Add all nodes to known_hosts first
ssh-keyscan 10.10.30.{1,2,3,11,12,13,51,52,53} 10.10.10.{8,10} >> ~/.ssh/known_hosts

# 2. Harden and configure all VMs (hostname, UFW, fail2ban, chrony, SSH hardening)
cd ansible/playbooks/ubuntu/new-host-bootstrap/
ansible-playbook main.yaml -i inventory.yaml

# 3. Install k3s
cd ansible/playbooks/kubernetes/k3s/new/
# Edit group_vars/all.yml: k3s_version, vip_ip=10.10.30.30, interface=eth0
ansible-playbook site.yml -i inventory.yaml

# 4. Install Docker on dock-prod
cd ansible/playbooks/docker/
ansible-playbook install-docker.yaml -i inventory.yaml
```

The k3s playbook handles:
- Longhorn prerequisites (`open-iscsi`, `nfs-common`) on all nodes
- k3s server init on master-1 with embedded etcd and kube-vip config
- k3s server join on master-2 and master-3
- k3s agent join on all workers and Longhorn nodes

Verify and copy kubeconfig:
```sh
# Check all 9 nodes are Ready
ssh hughboi@10.10.30.1 "sudo k3s kubectl get nodes"

# Copy kubeconfig locally — points to the VIP, not master-1 directly
ssh hughboi@10.10.30.1 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/10.10.30.30/' > ~/.kube/config
chmod 600 ~/.kube/config && kubectl get nodes
```

---

## Infrastructure Layer

Apply in this order — each depends on the previous:

### kube-vip (HA Control Plane VIP)

Provides a single stable IP (10.10.30.30) that floats between control plane nodes. `kubectl` and all agents point here regardless of which master is leader.

```sh
cd apps/kubernetes/k3s/infra/kube-vip/
# Edit daemonset.yaml: $interface=eth0, $vip=10.10.30.30
kubectl apply -f daemonset.yaml
kubectl rollout status daemonset/kube-vip -n kube-system

# Test from any machine:
kubectl --server=https://10.10.30.30:6443 get nodes
```

### MetalLB (Load Balancer)

Gives LoadBalancer services a real external IP from the pool (10.10.30.60–99).

```sh
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace
kubectl rollout status deployment/metallb-controller -n metallb-system
kubectl apply -f apps/kubernetes/k3s/infra/metallb/ip-address-pool.yaml
kubectl apply -f apps/kubernetes/k3s/infra/metallb/l2-advertisement.yaml
```

### Longhorn (Distributed Block Storage)

Turns the dedicated 200 GB disk on each Longhorn node into replicated block storage. Every PVC is replicated across nodes — a node failure doesn't lose data.

Verify prerequisites first:
```sh
ansible all -i ansible/playbooks/kubernetes/k3s/new/inventory.yaml \
  -m shell -a "dpkg -l open-iscsi nfs-common | grep ii" --become
```

```sh
kubectl apply -f apps/kubernetes/k3s/infra/longhorn/longhorn.yaml
kubectl rollout status daemonset/longhorn-manager -n longhorn-system --timeout=5m
kubectl patch storageclass longhorn \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Longhorn UI available at `10.10.30.50` (MetalLB VIP) after MetalLB is up.

### Sealed Secrets

Encrypt Kubernetes Secret objects so they can be safely committed to Git. **Install before ArgoCD** — ArgoCD will try to apply `SealedSecret` manifests on first sync and will fail if the controller isn't running.

```sh
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  -n kube-system \
  -f apps/kubernetes/k3s/infra/sealed-secrets/values.yaml
kubectl rollout status deployment/sealed-secrets -n kube-system

# Install kubeseal CLI (needed to seal secrets from your machine)
brew install kubeseal   # macOS — or download binary from releases page
```

> [!DANGER]
> **Backup the controller key immediately after install.** Losing this key means every sealed secret is permanently unrecoverable — you must re-seal everything from scratch.
> ```sh
> kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
>   -o yaml > ~/sealed-secrets-master.key
> # Store the contents in Vaultwarden — NEVER commit this file to git
> ```

Full install reference and migration guide: [`infra/sealed-secrets/`](../../../apps/kubernetes/k3s/infra/sealed-secrets/)

---

## Networking Layer

### cert-manager

Auto-provisions TLS certs from Let's Encrypt via Cloudflare DNS-01 challenge.

```sh
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set installCRDs=true

# Cloudflare token secret (imperative — never in git)
kubectl create secret generic cloudflare-token -n cert-manager \
  --from-literal=api-token=<your-cloudflare-token>

# Apply ClusterIssuer
kubectl apply -f apps/kubernetes/k3s/networking/traefik/helm/traefik/cert-manager/issuers/letsencrypt-production.yaml
```

### Reflector

Mirrors the wildcard TLS secret into every app namespace. Without it, each namespace needs its own copy of the cert.

```sh
helm install reflector emberstack/reflector -n kube-system
```

### Traefik + CrowdSec

```sh
cd apps/kubernetes/k3s/networking/traefik/

# Request wildcard cert first
kubectl apply -f helm/traefik/cert-manager/certificates/production/hughboi-production.yaml
kubectl get certificate -n traefik -w   # wait for Ready: True

# CrowdSec secrets (imperative)
kubectl create secret generic crowdsec-bouncer-key -n traefik \
  --from-literal=key=<bouncer-api-key>
helm install crowdsec crowdsec/crowdsec -n crowdsec --create-namespace -f helm/crowdsec/values.yaml

# Install Traefik
helm install traefik traefik/traefik -n traefik --create-namespace -f helm/traefik/values.yaml
kubectl apply -f helm/traefik/dashboard/
kubectl apply -f helm/traefik/default-headers.yaml manifest/bouncer-middleware.yaml

# Verify: Traefik should have EXTERNAL-IP 10.10.30.65
kubectl get svc -n traefik
```

### AdGuard (k3s DNS)

```sh
kubectl apply -f apps/kubernetes/k3s/networking/adguard/
```

Configure in AdGuard UI (`http://10.10.30.69`):
- Upstream DNS: `10.10.10.8` (Athena Bind9)
- DNS rewrites: `*.hughboi.vip → 10.10.30.65` (routes all k3s domains to Traefik)

**Split-DNS design:**
- `*.hughboi.cc` → Docker Traefik (dock-prod) — LAN DNS
- `*.hughboi.vip` → k3s Traefik — cluster internal
- Separate resolvers so k3s failure doesn't break LAN DNS

> This AdGuard-on-k3s instance is the target of the broader
> [DNS design](../1-networking/Unifi/Networks/DNS.md#target-dns-design-planned--not-yet-implemented)
> (AdGuard for WiFi/IoT/guest, forwarding local zones to Bind9). Its MetalLB VIP `10.10.30.69`
> is the `adguard-vip`.

---

## Platform Components

Beyond the core infra/networking layers, these run in the cluster (each has a full README in
`apps/kubernetes/k3s/`):

| Component | Role | Source |
| --- | --- | --- |
| **Velero** | Cluster-level DR — backs up **k8s resources + PVC data** to S3 (MinIO/B2), for full-cluster reconstruction. Complements Longhorn (which does volume-level restores). | [`infra/velero/`](../../apps/kubernetes/k3s/infra/velero/) |
| **system-upgrade-controller** | Automated k3s version upgrades via declarative `Plan`s — cordons/drains/upgrades/uncordons each node (servers first). No more SSH-per-node. | [`infra/system-upgrade-controller/`](../../apps/kubernetes/k3s/infra/system-upgrade-controller/) |
| **tailscale-operator** | Exposes individual Services on the tailnet (`tailscale.com/expose: "true"`) for remote admin (Grafana/ArgoCD/Longhorn) **without** public Traefik or open ports. | [`infra/tailscale-operator/`](../../apps/kubernetes/k3s/infra/tailscale-operator/) |
| **Authentik** | SSO / OIDC for k3s apps (forward-auth via Traefik). The k3s counterpart to Docker's Pocket ID — see [5-security identity](../5-security/index.md#identity--sso). | [`apps/authentik/`](../../apps/kubernetes/k3s/apps/authentik/) |

> **DR note:** Velero is the cluster-rebuild backup; **its S3 target is a required dependency** —
> stand up MinIO (TrueNAS) or B2 before relying on it, and include a Velero **restore** in the
> backup-validation drill (see backup testing).

---

## Observability

```sh
cd apps/kubernetes/k3s/monitoring/
kubectl apply -f namespace.yaml

# Wait for TLS secret reflection
kubectl get secret hughboi-tls -n monitoring -w

# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f kube-prometheus-stack/values.yaml \
  --set alertmanager.config.receivers[0].discord_configs[0].webhook_url=<discord-webhook>

# Loki + Alloy (log aggregation)
helm upgrade --install loki grafana/loki -n monitoring -f loki/values.yaml
helm upgrade --install alloy grafana/alloy -n monitoring -f alloy/values.yaml
```

Grafana at `https://grafana.hughboi.vip`. Pre-built dashboards for cluster, nodes, and Longhorn.

**Proxmox node metrics** — on each Proxmox node:
```sh
apt install prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```
Add scrape targets in Prometheus config for 10.10.10.1–4:9100.

**Essential alerts to configure:**
- Node unreachable
- Disk > 80% full
- Memory > 90%
- ZFS pool degraded
- k3s node NotReady
- Certificate expiry < 30 days
- Longhorn volume in degraded state
- PBS backup job failed

---

## GitOps (ArgoCD)

```sh
cd apps/kubernetes/k3s/argocd/
helm install argocd argo/argo-cd -n argocd --create-namespace -f install/values.yaml
kubectl rollout status deployment/argocd-server -n argocd
kubectl apply -f install/ingressroute.yaml

# Initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Register Gitea repo
argocd login argocd.hughboi.vip
argocd repo add https://gitea.hughboi.cc/hughboi/homelab.git \
  --username hughboi --password <gitea-token>

# Bootstrap App of Apps — ArgoCD now manages everything
kubectl apply -f apps/root-app.yaml
```

ArgoCD discovers every directory under `apps/kubernetes/k3s/apps/` automatically. New apps appear when you add a directory and push.

**Secrets via Sealed Secrets** — encrypted `SealedSecret` manifests live in git and ArgoCD applies them like any other manifest. The sealed-secrets controller (installed in Phase 9, before ArgoCD) decrypts them automatically. No pre-sync manual steps needed.

To seal a secret for a new app:
```sh
kubectl create secret generic my-app-secret -n my-app \
  --from-literal=api-key=<value> \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml
git add apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml && git commit && git push
```

If a pod crashes on first sync, check the app's `secret.yaml` for any remaining imperative secrets (some apps may not be migrated to Sealed Secrets yet).

### Adding a New k3s App

1. Create `apps/kubernetes/k3s/apps/<name>/` with namespace, deployment, service, IngressRoute
2. Seal any secrets: `kubectl create secret ... --dry-run=client -o yaml | kubeseal --format yaml > sealed-secret.yaml`
3. `git add . && git commit && git push`
4. ArgoCD discovers the new directory and syncs within 3 minutes
5. Check ArgoCD UI to confirm sync succeeded

---

## Semaphore Scheduled Jobs {#semaphore-jobs}

| Playbook | Schedule | Purpose |
| --- | --- | --- |
| `ubuntu/check-disk-space` | Daily | Catch full disks before outages |
| `docker/compose-health` | Daily | Catch containers that crashed overnight |
| `ubuntu/time-sync-check` | Daily | k3s is sensitive to clock drift |
| `ubuntu/nfs-health` | Daily | Catch stale NFS mounts |
| `ubuntu/ssl-cert-expiry` | Daily | Know before users see cert warnings |
| `vaultwarden/backup` | Daily | Password manager backup |
| `kubernetes/k3s/etcd-backup` | Daily | Full cluster state backup |
| `ubuntu/disk-health` | Weekly | SMART warnings before drive failure |
| `ubuntu/fail2ban-report` | Weekly | Security situational awareness |
| `ubuntu/journal-cleanup` | Weekly | Prevent log disk fill |
| `docker/volume-backup` | Weekly | Named Docker volume backup to TrueNAS |
| `docker/postgres-maintenance` | Monthly | VACUUM ANALYZE on all Postgres |
| `ubuntu/audit-users` | Monthly | Check for unexpected accounts |
| `ubuntu/audit-listening-ports` | Monthly | Catch unexpected exposed ports |
| `ubuntu/lynis-scan` | Quarterly | Full security hardening score |
| `proxmox/vm-inventory` | On-demand | Before/after infrastructure changes |
| `proxmox/storage-report` | On-demand | When checking capacity |

---

## Best Practices

**Resource limits on every workload** — without `resources.limits`, one misbehaving app can starve a node:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

**PodDisruptionBudgets for critical apps** — prevents node drains from taking all replicas down simultaneously:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

**Pin image versions** — never use `:latest` in production. Renovate Bot opens PRs automatically when new versions are available:
```json
{ "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "gitAuthor": "Renovate Bot <renovate@hughboi.cc>" }
```

---

## Troubleshooting {#troubleshooting}

| Problem | Action |
| --- | --- |
| Nodes NotReady after deploy | `kubectl describe node <name>` — check Longhorn, check VLAN 30/40 routing |
| Longhorn volume degraded | Longhorn UI → identify degraded replica → trigger rebuild |
| ArgoCD not syncing | Check Gitea webhooks; `argocd app sync <app>` |
| SOPS decrypt fails | Verify `SOPS_AGE_KEY_FILE` env var on Athena |
| cert-manager not issuing | Check Cloudflare token secret exists in `cert-manager` namespace |
| Traefik no EXTERNAL-IP | MetalLB must be running; check L2Advertisement covers the IP |
| Pod crashlooping on start | Missing secret — check if `SealedSecret` was committed and synced; or check `secret.yaml` for any remaining imperative secrets |
| k3s nodes can't reach Athena | Firewall rule: K3S → MGMT is DENY by design — use polling from Athena |
| Longhorn prereqs missing | Run `open-iscsi` / `nfs-common` check via Ansible on all nodes |
| Sealed Secrets won't decrypt | Key backup in Vaultwarden? If key is lost, must re-seal all secrets |
