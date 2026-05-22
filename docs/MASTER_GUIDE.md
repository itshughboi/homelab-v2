# Homelab Master Guide

> Quick runbook — follow phases top to bottom to rebuild from bare metal.
> For deep context (why decisions were made, architecture detail, troubleshooting), see the numbered section folders.

---

## Quick Reference

| Thing | Value |
| --- | --- |
| Proxmox UI | https://10.10.10.1:8006 (root / PVE password) |
| Athena SSH | `ssh hughboi@10.10.10.8` |
| dock-prod SSH | `ssh hughboi@10.10.10.10` |
| Gitea | https://gitea.hughboi.cc |
| Semaphore | https://semaphore.hughboi.cc |
| Vaultwarden | https://vault.hughboi.cc |
| Bind9 DNS | 10.10.10.8:53 |
| Netboot | http://10.10.99.99:8080 |
| k3s API VIP | 10.10.30.30:6443 |
| Template VM ID | 9999 (bottom of Proxmox list) |

**VLAN cheat sheet:**
- `10` Management — 10.10.10.0/24 — gateway 10.10.10.254
- `20` Cluster (Corosync only) — 10.10.20.0/24 — **no gateway, no MTU change**
- `30` k3s — 10.10.30.0/24
- `40` Storage — 10.10.40.0/24 — **MTU 9000 everywhere**
- `49` Torrent — 172.16.20.0/24 — airgapped
- `80` VPN — 10.10.80.0/24
- `99` Provisioning — 10.10.99.0/24

→ Full IP/VLAN/service reference: [1-prep](1-prep/index.md)

---

## Before You Start

Gather these credentials before touching hardware — you will get blocked without them:

- [ ] Cloudflare API Token (Zone:DNS:Edit) + Zone ID
- [ ] Discord webhook URL
- [ ] SSH public key: `cat ~/.ssh/id_ed25519.pub`
- [ ] Proxmox API token (created in Phase 4 — have a password manager ready)

Tooling on your laptop:
```sh
brew install terraform ansible packer git age sops helm
```

Generate a dedicated homelab SSH keypair (don't reuse your personal key):
```sh
ssh-keygen -t ed25519 -C "homelab-datacenter" -f ~/.ssh/homelab_id_ed25519
```

---

## Phase 1 — Network (UniFi)

**Goal:** VLAN-aware network with PXE boot support.

- [ ] Create VLANs 10, 20, 30, 40, 49, 80, 99 in UniFi
- [ ] Set VLAN 99 DHCP options: Option 66 = `10.10.99.99`, Option 67 = `ipxe.efi`
- [ ] Set MTU 9000 on switch ports carrying VLAN 40
- [ ] Assign switch ports: UXG Max Port 2 → VLAN 99 (untagged), Ports 3–5 → trunk
- [ ] Add MAC reservations for all infrastructure nodes
- [ ] Enable "Block inter-VLAN traffic" in Network settings
- [ ] Add first firewall rule: `ALLOW ALL → ALL  state: established, related`
- [ ] Add remaining firewall rules by VLAN (see Phase 1 detail)

→ [Full networking detail](2-networking/index.md)

---

## Phase 2 — PXE Netboot

**Goal:** Libre Potato serves automated Proxmox installs over the network.

For each node, before powering it on:
- [ ] Create TOML at `bootstrap/netbootxyz/config/proxmox/pve-srv-X.toml`
- [ ] Add MAC → hostname entry in `local.ipxe`
- [ ] Add MAC reservation in UniFi (VLAN 10)
- [ ] Enable PXE boot in node BIOS, boot order: PXE first, Secure Boot: OFF

Verify serving before booting anything:
```sh
curl -I http://10.10.99.99:8080/ipxe.efi
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
# Both must return 200 OK
```

Boot each node:
1. Plug into UXG Max Port 3 (VLAN 99) → power on → wait for Proxmox login prompt
2. Verify: `ssh root@10.10.10.X`
3. Move cable to permanent trunk port (USW Flex Mini)

Fallback if Libre Potato is dead: [Ventoy USB](1-prep/index.md#ventoy-fallback)

→ [Full PXE detail](1-prep/index.md)

---

## Phase 3 — TrueNAS

**Goal:** NFS shares available before any Docker services that depend on them start.

- [ ] Configure ZFS pools (see storage reference for layout)
- [ ] Create NFS datasets: `YT-Audios`, `Restic`, `k3s-backups`, `pbs-storage/datastore1`
- [ ] Set permissions per dataset (YT-Audios: mapall root; others: `hughboi:hughboi`)
- [ ] Use bridge interface `br0` inside TrueNAS — never assign IPs to raw NICs
- [ ] Test MTU 9000 on VLAN 40: `ping -M do -s 8972 10.10.40.X`

→ [Full storage detail](5-storage/index.md)

---

## Phase 4 — Proxmox Cluster

**Goal:** 4-node cluster with HA quorum.

On each node — disable enterprise repo:
```sh
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
apt update && apt dist-upgrade -y
```

Form cluster (on pve-srv-1, then join from others):
```sh
# pve-srv-1:
pvecm create homelab

# pve-srv-2/3/4:
pvecm add 10.10.10.1

# Verify:
pvecm status  # look for: Quorate: Yes
```

Create API tokens:
```sh
# Terraform token
pveum user add terraform@pve && pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve terraform --privsep=0
# Copy token immediately — shown once. Store in Vaultwarden.

# Packer token
pveum user add packer@pve && pveum aclmod / -user packer@pve -role Administrator
pveum user token add packer@pve packer --privsep=0
```

Add virtual interfaces on each node (in Proxmox UI → System → Network):
- `vmbr0.10` VLAN 10 MTU 1500 (Management)
- `vmbr0.20` VLAN 20 MTU 1500 (Cluster — apply QoS DSCP 46)
- `vmbr0.30` VLAN 30 MTU 1500 (k3s)
- `vmbr0.40` VLAN 40 MTU 9000 (Storage — Jumbo Frames)

QDevice setup (do after Phase 8 when Athena is running):
```sh
# On Athena
apt install corosync-qnetd

# On any Proxmox node
pvecm qdevice setup 10.10.10.8
pvecm status  # QDevice should appear
```

→ [Full Proxmox detail](3-proxmox/provisioning/index.md)

---

## Phase 5 — VM Template (ID 9999)

**Goal:** Ubuntu 24.04 cloud-init template all other VMs clone from.

Option A — Ansible playbook (recommended):
```sh
cd ansible/playbooks/proxmox/vm-template-refresh/
ansible-playbook main.yaml -i inventory.yaml
```

Option B — Packer (for custom packages baked in):
```sh
cd packer/proxmox-iso-ubuntu/
cp proxmox.pkrvars.sh.example proxmox.pkrvars.sh
$EDITOR proxmox.pkrvars.sh
./build.sh
```

Verify: template VM 9999 appears in Proxmox UI on pve-srv-1 with template icon.

→ [Full template detail](3-proxmox/provisioning/index.md#vm-template)

---

## Phase 6 — Terraform: Provision VMs

**Goal:** all VMs exist and are running.

```sh
cd terraform/proxmox/
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars  # fill in: proxmox_api_url, proxmox_api_token, ssh_public_key

terraform init
terraform plan   # review: expect athena, dock-prod, 9× k3s nodes
terraform apply  # wait 60–90s after for cloud-init to finish
```

Verify: `ssh hughboi@10.10.30.1 "echo ok"` (k3s-master-1)

→ [VM spec table / Terraform detail](3-proxmox/provisioning/index.md#terraform)

---

## Phase 7 — Ansible: Bootstrap All VMs

**Goal:** every VM hardened and configured.

```sh
# Add all hosts to known_hosts
ssh-keyscan 10.10.30.{1,2,3,11,12,13,51,52,53} 10.10.10.{8,10} >> ~/.ssh/known_hosts

# Bootstrap (hostname, UFW, fail2ban, chrony, SSH hardening, MOTD)
cd ansible/playbooks/ubuntu/new-host-bootstrap/
ansible-playbook main.yaml -i inventory.yaml

# Install k3s
cd ansible/playbooks/kubernetes/k3s/new/
# Edit group_vars/all.yml: k3s_version, vip_ip=10.10.30.30, interface=eth0
ansible-playbook site.yml -i inventory.yaml

# Docker on dock-prod
cd ansible/playbooks/docker/
ansible-playbook install-docker.yaml -i inventory.yaml
```

Verify cluster:
```sh
ssh hughboi@10.10.30.1 "sudo k3s kubectl get nodes"
# All 9 nodes should be Ready within 2-3 minutes

# Copy kubeconfig locally
ssh hughboi@10.10.30.1 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/10.10.30.30/' > ~/.kube/config
chmod 600 ~/.kube/config && kubectl get nodes
```

---

## Phase 8 — Athena: Management Plane

**Goal:** Athena becomes the control center. Laptop retires.

```sh
# Bootstrap Athena from laptop
ansible-playbook ansible/playbooks/ubuntu/setup-athena/main.yaml \
  -i ansible/playbooks/ubuntu/setup-athena/inventory.yaml
```

SOPS setup (on Athena — do before pushing any secrets):
```sh
apt install age sops
age-keygen -o ~/.config/sops/age/keys.txt  # copy the public key output
./scripts/age-setup.sh                      # populates .sops.yaml in repo
```

Start Docker services in order — DNS/proxy first, everything else after:
```sh
# 1. DNS + proxy (everything else depends on these)
cd apps/docker/bind9 && docker compose up -d
cd apps/docker/adguard && docker compose up -d
cd apps/docker/traefik && docker compose up -d   # fill .env first

# 2. Security
cd apps/docker/crowdsec && docker compose up -d
docker exec crowdsec cscli bouncers add traefik-bouncer
# → copy key → add to traefik/.env as CROWDSEC_BOUNCER_API_KEY → docker restart traefik

# 3. Notifications (so playbooks can alert you going forward)
cd apps/docker/ntfy && docker compose up -d
cd apps/docker/mailrise && docker compose up -d

# 4. Password manager
cd apps/docker/vaultwarden && docker compose up -d

# 5. Git + Ansible UI
cd apps/docker/gitea && docker compose up -d
cd apps/docker/semaphore && docker compose up -d

# 6. Push repo to Gitea, retire laptop
git remote add gitea https://gitea.hughboi.cc/hughboi/homelab.git
git push gitea main
```

Set up Semaphore at `semaphore.hughboi.cc`: SSH key, Gitea repo, inventory → `ansible/inventories/`.

Start remaining Docker services (see [7-docker](7-docker/index.md) for full ordered list).

→ [Full Athena/Docker detail](4-athena/index.md) · [Docker services reference](7-docker/index.md)

---

## Phase 9 — k3s Infrastructure Layer

Apply in order — each step depends on the previous.

```sh
# kube-vip (HA control plane VIP — 10.10.30.30)
cd apps/kubernetes/k3s/infra/kube-vip/
# Edit daemonset.yaml: $interface=eth0, $vip=10.10.30.30
kubectl apply -f daemonset.yaml
kubectl rollout status daemonset/kube-vip -n kube-system

# MetalLB (load balancer, pool 10.10.30.60–99)
cd apps/kubernetes/k3s/infra/metallb/
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace
kubectl apply -f ip-address-pool.yaml && kubectl apply -f l2-advertisement.yaml

# Longhorn (distributed storage across workers)
cd apps/kubernetes/k3s/infra/longhorn/
kubectl apply -f longhorn.yaml
kubectl rollout status daemonset/longhorn-manager -n longhorn-system --timeout=5m
kubectl patch storageclass longhorn \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Sealed Secrets (MUST be BEFORE ArgoCD — ArgoCD will try to apply SealedSecrets on first sync)
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  -n kube-system \
  -f apps/kubernetes/k3s/infra/sealed-secrets/values.yaml
kubectl rollout status deployment/sealed-secrets -n kube-system

# Install kubeseal CLI (needed to seal secrets from your machine)
brew install kubeseal   # or download binary from releases page

# Backup controller key IMMEDIATELY — if this key is lost, all sealed secrets are unrecoverable
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-master.key
# → Open Vaultwarden and store the contents of sealed-secrets-master.key there
# → DO NOT commit this file to git
```

→ [Full k3s infrastructure detail](8-k3s/index.md)

---

## Phase 10 — k3s Networking Layer

```sh
# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set installCRDs=true
kubectl create secret generic cloudflare-token -n cert-manager \
  --from-literal=api-token=<your-cloudflare-token>
kubectl apply -f apps/kubernetes/k3s/networking/traefik/helm/traefik/cert-manager/issuers/letsencrypt-production.yaml

# Reflector (mirrors TLS certs into all namespaces)
helm repo add emberstack https://emberstack.github.io/helm-charts
helm install reflector emberstack/reflector -n kube-system

# Request wildcard cert (DNS-01 via Cloudflare, usually 30-90 sec)
cd apps/kubernetes/k3s/networking/traefik/
kubectl apply -f helm/traefik/cert-manager/certificates/production/hughboi-production.yaml
kubectl get certificate -n traefik -w   # wait for Ready: True

# CrowdSec + Traefik (see traefik/README.md for full sequence)
kubectl create secret generic crowdsec-bouncer-key -n traefik \
  --from-literal=key=<your-bouncer-key>
helm install crowdsec crowdsec/crowdsec -n crowdsec --create-namespace -f helm/crowdsec/values.yaml
helm install traefik traefik/traefik -n traefik --create-namespace -f helm/traefik/values.yaml
kubectl apply -f helm/traefik/dashboard/ -f helm/traefik/default-headers.yaml
kubectl apply -f manifest/bouncer-middleware.yaml
# Verify: kubectl get svc -n traefik → EXTERNAL-IP should be 10.10.30.65

# AdGuard
kubectl apply -f apps/kubernetes/k3s/networking/adguard/
# Configure at 10.10.30.69: upstream DNS = 10.10.10.8, rewrites *.hughboi.vip → 10.10.30.65

# Network policies
kubectl apply -f apps/kubernetes/k3s/networking/network-policies/
```

---

## Phase 11 — Observability

```sh
cd apps/kubernetes/k3s/monitoring/
kubectl apply -f namespace.yaml
kubectl get secret hughboi-tls -n monitoring -w   # wait for TLS reflection

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f kube-prometheus-stack/values.yaml \
  --set alertmanager.config.receivers[0].discord_configs[0].webhook_url=<discord-webhook>

helm upgrade --install loki grafana/loki -n monitoring -f loki/values.yaml
helm upgrade --install alloy grafana/alloy -n monitoring -f alloy/values.yaml
```

On each Proxmox node:
```sh
apt install prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```

→ Grafana at https://grafana.hughboi.vip

---

## Phase 12 — GitOps (ArgoCD)

```sh
cd apps/kubernetes/k3s/argocd/
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f install/values.yaml
kubectl rollout status deployment/argocd-server -n argocd
kubectl apply -f install/ingressroute.yaml

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Register Gitea repo
argocd login argocd.hughboi.vip
argocd repo add https://gitea.hughboi.cc/hughboi/homelab.git \
  --username hughboi --password <gitea-token>

# Bootstrap App of Apps — ArgoCD now manages everything
kubectl apply -f apps/root-app.yaml
```

**Secrets are handled via Sealed Secrets** — encrypted `SealedSecret` manifests live in git. ArgoCD applies them and the controller decrypts them automatically. No manual `kubectl create secret` needed for sealed secrets. If a pod crashes on first sync, check the app's `secret.yaml` — some apps may still use imperative secrets during early migration.

→ [Full GitOps detail](9-gitops/index.md)

---

## Phase 13 — Scheduled Maintenance

Wire up in Semaphore UI. See [scheduled jobs table](8-k3s/index.md#semaphore-jobs) for the full list.

Critical ones to set up immediately:
- `kubernetes/k3s/etcd-backup` — Daily (your entire cluster state)
- `vaultwarden/backup` — Daily
- `ubuntu/check-disk-space` — Daily
- `docker/compose-health` — Daily
- `ubuntu/ssl-cert-expiry` — Daily

---

## Break-Glass Quick Reference

| Problem | Fix |
| --- | --- |
| Node SSH unreachable | Serial console: `screen /dev/cu.usbserial-XXXX 115200` |
| Cluster lost quorum | `pvecm status` → check QDevice on Athena |
| Corosync fencing loop | Stop problem node, check VLAN 20 QoS/saturation |
| k3s nodes NotReady | `kubectl describe node <name>` → check Longhorn, VLAN 30/40 |
| Longhorn volume degraded | Longhorn UI → identify degraded replica → trigger rebuild |
| ArgoCD out of sync | `argocd app sync <app>` — check Gitea webhooks |
| SOPS decrypt fails | Check `SOPS_AGE_KEY_FILE` env var on Athena |
| DNS broken | `dig @10.10.10.8 <hostname>` — tests Bind9 directly |
| PBS write fails | Check NFS mount + ACLs (UID 2147000035) |
| Storage VLAN packet loss | `ping -M do -s 8972 10.10.40.X` — MTU must be 9000 end-to-end |
| Netboot 404 | Check `local.ipxe` MAC mapping + file exists in `assets/proxmox/` |
| Sealed Secrets lost | Must re-seal all secrets — verify backup is in Vaultwarden |

→ [Full troubleshooting](8-k3s/index.md#troubleshooting)
