# k3s Homelab Cluster

3-master, 3-worker k3s cluster with dedicated Longhorn storage nodes. All user-facing services resolve to `*.hughboi.cc` via Traefik.

> Docker services (legacy) run on `*.hughboi.cc`. The goal is to migrate everything here.  
> Monitoring tools (InfluxDB, Telegraf, Promtail/Grafana Agent) have been replaced cluster-wide by the kube-prometheus-stack + Loki + Alloy stack in `monitoring/`.

---

## Node Map

| Host | IP | Role |
|------|----|------|
| k3s-master-1 | 10.10.30.1 | Control plane |
| k3s-master-2 | 10.10.30.2 | Control plane |
| k3s-master-3 | 10.10.30.3 | Control plane |
| k3s-worker-1 | 10.10.30.11 | Worker |
| k3s-worker-2 | 10.10.30.12 | Worker |
| k3s-worker-3 | 10.10.30.13 | Worker |
| k3s-api-vip | 10.10.30.30 | kube-vip control-plane VIP |
| k3s-longhorn-vip | 10.10.30.50 | Longhorn UI |
| k3s-longhorn-1 | 10.10.30.51 | Longhorn storage node |
| k3s-longhorn-2 | 10.10.30.52 | Longhorn storage node |
| k3s-longhorn-3 | 10.10.30.53 | Longhorn storage node |

**MetalLB pool:** `10.10.30.60 – 10.10.30.99`

| Service | IP |
|---------|----|
| AdGuard DNS | 10.10.30.65 |
| Traefik ingress | 10.10.30.75 |

---

## Directory Layout

```
k3s/
├── infra/              # Cluster-level infrastructure (apply first)
│   ├── kube-vip/       # Control-plane HA VIP (ARP, control plane only)
│   ├── metallb/        # L2 LoadBalancer IP pool
│   └── longhorn/       # Distributed block storage (default StorageClass)
├── networking/         # Network services (apply second)
│   ├── traefik/        # Ingress controller + cert-manager + CrowdSec + Reflector
│   └── adguard/        # DNS ad blocking
├── monitoring/         # Observability stack (apply third)
│   ├── namespace.yaml
│   ├── kube-prometheus-stack/  # Prometheus + Grafana + Alertmanager
│   ├── loki/           # Log storage
│   └── alloy/          # Log + metrics collector (replaces Promtail + Grafana Agent)
└── apps/               # User-facing applications
    ├── fasten-health/
    ├── freshrss/
    ├── gatus/
    ├── gitea/
    ├── hoarder/
    ├── home-assistant/
    ├── homepage/
    ├── immich/
    ├── jellyfin/
    ├── mailrise/
    ├── mealie/
    ├── n8n/
    ├── netbootxyz/
    ├── ntfy/
    ├── paperless-ngx/
    ├── pocket-id/
    ├── romm/
    ├── searxng/
    ├── semaphore/
    ├── syncthing/
    ├── tube-archivist/
    ├── unifi/           # TEST ONLY — re-adoption required for production cutover
    └── vaultwarden/
```

---

## Bootstrap Order

Each layer depends on the one above it being healthy first.

### 1. Infra

```bash
# kube-vip — fill $interface and $vip placeholders first
kubectl apply -f infra/kube-vip/daemonset.yaml

# MetalLB — fill $lbrange first
helm install metallb metallb/metallb -n metallb-system --create-namespace
kubectl apply -f infra/metallb/ip-address-pool.yaml
kubectl apply -f infra/metallb/l2-advertisement.yaml

# Longhorn — requires open-iscsi + nfs-common on all nodes
kubectl apply -f infra/longhorn/longhorn.yaml
kubectl rollout status daemonset/longhorn-manager -n longhorn-system
```

### 2. Networking

See [networking/traefik/README.md](networking/traefik/README.md) for the full cert-manager + Reflector + Traefik + CrowdSec deploy sequence.

```bash
# After Traefik is up
kubectl apply -f networking/adguard/
```

### 3. Monitoring

See [monitoring/README.md](monitoring/README.md) for Helm commands and verify steps.

### 4. Apps

Each app directory has its own README with deploy order and prerequisites. General pattern:

```bash
kubectl apply -f apps/<name>/namespace.yaml
kubectl apply -f apps/<name>/secret.yaml   # fill values first
kubectl apply -f apps/<name>/           # remaining manifests
```

---

## TLS

Wildcard cert `*.hughboi.cc` is issued by cert-manager via Cloudflare DNS-01 and stored as `hughboi-tls` in the `traefik` namespace. Reflector mirrors it automatically to all app namespaces.

**When adding a new app:** add its namespace to the Reflector annotation in  
`networking/traefik/helm/traefik/cert-manager/certificates/production/hughboi-production.yaml`

---

## Replaced Tools

The following Docker-stack tools are **not deployed here** — their functionality is covered by the monitoring stack:

| Docker tool | Replaced by |
|-------------|-------------|
| InfluxDB | Prometheus (metrics storage) |
| Telegraf | node-exporter + kube-state-metrics |
| Promtail | Grafana Alloy |
| Grafana Agent | Grafana Alloy |
| Proxmox InfluxDB push | prometheus-pve-exporter (apps/prometheus-pve-exporter/) |

---

## Day-2 Operations

### Draining a node for maintenance

```bash
# Cordon + drain — evicts all pods (respects PodDisruptionBudgets)
kubectl drain k3s-worker-1 --ignore-daemonsets --delete-emptydir-data

# Do your maintenance (reboot, hardware swap, k3s upgrade, etc.)

# Uncordon to allow scheduling again
kubectl uncordon k3s-worker-1
```

> If a drain hangs, check which PDB is blocking it:
> ```bash
> kubectl get pdb -A
> kubectl describe pdb <name> -n <namespace>
> ```

### Checking cluster health

```bash
# Node status
kubectl get nodes -o wide

# Pod health across all namespaces
kubectl get pods -A | grep -v Running | grep -v Completed

# Recent events (errors, warnings)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# ArgoCD sync status
kubectl get applications -n argocd

# Certificate health
kubectl get certificates -A
kubectl get certificaterequests -A
```

### Longhorn storage health

```bash
# Check volume health
kubectl get volumes -n longhorn-system

# Check node disk status
kubectl get nodes -n longhorn-system

# Access Longhorn UI directly
# http://10.10.30.50  (MetalLB LoadBalancer)
```

### Adding a new app to GitOps

1. Create `apps/kubernetes/k3s/apps/<appname>/` directory
2. Add standard manifests: `namespace.yaml`, `secret.yaml`, `deployment.yaml`, `service.yaml`, `ingressroute.yaml`
3. Add the namespace to the Reflector annotation in `networking/traefik/helm/traefik/cert-manager/certificates/production/hughboi-production.yaml`
4. Create the secret imperatively on the cluster: `kubectl create secret generic ...`
5. Push to `main` — ArgoCD auto-discovers the new directory via the ApplicationSet and syncs it

### Forcing an ArgoCD sync

```bash
# Sync a single app
argocd app sync <appname>

# Hard refresh (ignores cache)
argocd app sync <appname> --force

# Sync all apps
argocd app sync --selector '!argocd.argoproj.io/skip-reconcile'
```

### Viewing logs

```bash
# Real-time pod logs
kubectl logs -f deployment/<name> -n <namespace>

# Previous container logs (after crash/restart)
kubectl logs deployment/<name> -n <namespace> --previous

# All logs via Loki (Grafana → Explore → Loki)
# Filter: {namespace="<ns>", app="<name>"}
```

---

## Upgrading k3s

> Always snapshot Proxmox VMs before upgrading. system-upgrade-controller handles rolling upgrades automatically when you push a new Plan version.

### Automated (system-upgrade-controller)

The Plans in `infra/system-upgrade-controller/` target the `stable` channel. To trigger an upgrade:

```bash
# Check current version
kubectl get nodes -o wide

# Check available stable version
curl -s https://update.k3s.io/v1-release/channels | jq '.data[] | select(.name=="stable") | .latest'

# Update the version in infra/system-upgrade-controller/plans/
# Push to main → ArgoCD applies the updated Plan → SUC rolls out upgrade node by node
```

### Manual upgrade (single node)

```bash
# On the target node
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.31.X+k3s1 sh -

# Verify
k3s --version
kubectl get nodes
```

### Upgrade order
1. Drain master nodes one at a time (kube-vip handles VIP failover)
2. Upgrade workers after all masters are on the new version
3. Longhorn nodes last (storage nodes carry data)

---

## Disaster Recovery

### Full cluster rebuild

1. Restore sealed-secrets master key FIRST (from Vaultwarden):
   ```bash
   kubectl apply -f sealed-secrets-master.key
   helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system -f infra/sealed-secrets/values.yaml
   ```
2. Follow Bootstrap Order above (infra → networking → monitoring → ArgoCD)
3. ArgoCD re-syncs all apps from this repo — all SealedSecrets decrypt automatically
4. Restore PVC data from Velero: `velero restore create --from-backup <latest>`

### Restore a single volume from Longhorn backup

```bash
# In Longhorn UI: Volumes → <vol> → Restore Backup
# Or via kubectl:
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: <restore-name>
  namespace: longhorn-system
spec:
  fromBackup: "s3://homelab-longhorn@us-east-1/?backup=<id>&volume=<vol-name>"
  numberOfReplicas: 3
  size: "10Gi"
EOF
```

### etcd backup (k3s embedded)

k3s uses embedded etcd. Snapshots are taken automatically every 12h and kept for 5 days at `/var/lib/rancher/k3s/server/db/snapshots/` on each master.

```bash
# Manual snapshot
k3s etcd-snapshot save --name manual-$(date +%Y%m%d)

# List snapshots
k3s etcd-snapshot list

# Restore (run on first master, with cluster stopped)
k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-path>
```

---

## Troubleshooting

### ArgoCD stuck in "Unknown" or won't sync

```bash
# Check ArgoCD can reach Gitea
kubectl exec -n argocd deploy/argocd-server -- \
  curl -s http://gitea.gitea.svc.cluster.local:3000

# Check repo server logs
kubectl logs -n argocd deploy/argocd-repo-server --tail=50

# Force refresh
argocd app get <appname> --refresh
```

### Pod stuck in Pending

```bash
kubectl describe pod <pod> -n <namespace>
# Look for: Insufficient CPU/memory, no matching nodes, PVC not bound

# Check PVC status
kubectl get pvc -n <namespace>

# Check Longhorn volume
kubectl get volumes -n longhorn-system | grep <pvc-name>
```

### Certificate not issuing

```bash
kubectl describe certificate hughboi-production -n traefik
kubectl describe certificaterequest -n traefik
kubectl logs -n cert-manager deploy/cert-manager

# Check Cloudflare API token is valid
kubectl get secret cloudflare-api-token -n cert-manager -o yaml
```

### CrowdSec blocking legitimate traffic

```bash
# List active decisions
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions list

# Remove a specific IP ban
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli decisions delete -i <IP>

# Check bouncer logs
kubectl logs -n traefik deploy/traefik | grep crowdsec
```

---

## Setup Reference

Ansible k3s install playbook: `ansible/playbooks/kubernetes/k3s/`
