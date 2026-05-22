# k3s Automated Bootstrap Playbooks

Fully automated Ansible playbooks for bootstrapping and configuring the k3s homelab cluster. These live alongside the original manual notes (`../README.md`) — the originals are kept as reference.

## What's improved over the manual process

| Area | Before (manual) | After (these playbooks) |
|------|-----------------|------------------------|
| Node prep | Manual apt installs, manual sysctl edits | Automated, idempotent, with Longhorn multipath fix |
| k3s install | External GitHub script (`k3s-deploy.sh`) | Version-pinned, vault-secured, HA-aware |
| kube-vip | Deployed post-init via kubectl | Placed in auto-deploy manifests dir before k3s starts — VIP available immediately |
| Join order | Manual, error-prone | Enforced: init → additional masters (serial) → agents |
| Longhorn disk | Manual format + mount | Automated detection, format, mount, iSCSI config |
| Node labels | Manual kubectl commands | Applied automatically in post-install |
| Kubeconfig | Manual SSH + copy + edit | Fetched, VIP-patched, and saved locally automatically |
| Vault secret | Plaintext in script | Ansible Vault encrypted |
| Idempotency | None — re-running would break things | Full — re-run any stage safely |

---

## Prerequisites

### On the Ansible controller (your Mac/workstation)

```bash
# Install Ansible
pip install ansible ansible-lint

# Install required collections
ansible-galaxy collection install ansible.posix community.general

# Verify connectivity (run from this directory)
ansible all -i inventory.yaml -m ping --ask-pass
# Or if SSH keys are already deployed:
ansible all -i inventory.yaml -m ping
```

### On the k3s nodes

Nodes must be freshly provisioned from the Packer/Terraform template:
- Ubuntu 22.04+ (cloud-init template)
- SSH key deployed (via cloud-init)
- DHCP reservations set in Unifi (IPs match inventory.yaml)
- **Take a Proxmox snapshot of each VM before proceeding**

### Ansible Vault

Set up the cluster secret before running anything:

```bash
# Generate a strong random secret
openssl rand -hex 32

# Edit the vault file and paste the output
ansible-vault edit group_vars/vault.yml
# Set: vault_k3s_cluster_secret: "<paste-here>"

# Create a vault password file so you don't have to type it every run
echo "your-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

---

## Variables to review before running

Open `group_vars/all.yml` and verify:

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_version` | `v1.31.4+k3s1` | Pin to a specific release |
| `k3s_api_vip` | `10.10.30.30` | kube-vip VIP for control plane |
| `kube_vip_version` | `v0.8.2` | Must match `infra/kube-vip/daemonset.yaml` |
| `vip_interface` | `eth0` | Run `ip link` on a master to confirm |
| `k3s_server_extra_args` | see file | Disables built-in Traefik + ServiceLB |

---

## Running the playbooks

### Step 1 — Preflight check (no changes, just validates)

```bash
ansible-playbook -i inventory.yaml preflight.yml \
  --vault-password-file ~/.vault_pass
```

Expected output:
```
Preflight checks passed ✓
  k3s version:   v1.31.4+k3s1
  API VIP:       10.10.30.30:6443
  VIP interface: eth0
  ...
  Ready to run: ansible-playbook -i inventory.yaml site.yml
```

Fix any failures before proceeding.

### Step 2 — Full bootstrap

```bash
ansible-playbook -i inventory.yaml site.yml \
  --vault-password-file ~/.vault_pass
```

Estimated time: 10–15 minutes for a 9-node cluster.

### Step 3 — Verify from your local machine

```bash
# The kubeconfig is saved to ~/.kube/homelab-k3s.yaml
export KUBECONFIG=~/.kube/homelab-k3s.yaml

kubectl get nodes -o wide
# All 9 nodes should show "Ready"

kubectl get pods -A
# Only kube-system pods at this point — apps come from ArgoCD
```

---

## Running individual stages

Each stage has a tag — you can run just the parts you need:

```bash
# Re-run only system prereqs (safe to re-run any time)
ansible-playbook -i inventory.yaml site.yml --tags prereqs \
  --vault-password-file ~/.vault_pass

# Re-run only Longhorn disk prep on storage nodes
ansible-playbook -i inventory.yaml site.yml --tags longhorn \
  --vault-password-file ~/.vault_pass

# Re-run only post-install (labels, taints, kubeconfig)
ansible-playbook -i inventory.yaml site.yml --tags post \
  --vault-password-file ~/.vault_pass
```

Tags available: `prereqs`, `longhorn`, `init`, `servers`, `agents`, `post`, `labels`, `kubeconfig`, `verify`, `stage1`–`stage6`

---

## Adding a node after initial setup

### Add a new worker node

1. Provision the VM with Terraform (`terraform apply` in `terraform/proxmox/`)
2. Add it to `inventory.yaml` under `k3s_workers`
3. Run prereqs + agent join on just the new node:
   ```bash
   ansible-playbook -i inventory.yaml site.yml \
     --limit new-worker-hostname \
     --tags prereqs,agents \
     --vault-password-file ~/.vault_pass
   ```

### Add a new Longhorn storage node

Same as above but under `k3s_longhorn` in inventory, then:
```bash
ansible-playbook -i inventory.yaml site.yml \
  --limit new-longhorn-hostname \
  --tags prereqs,longhorn,agents,labels \
  --vault-password-file ~/.vault_pass
```

---

## Upgrading k3s

> **Always snapshot Proxmox VMs before upgrading.**

The system-upgrade-controller (deployed via ArgoCD) handles rolling upgrades automatically. Update the version in `infra/system-upgrade-controller/plans.yaml` and push to Git — ArgoCD applies it and the controller rolls upgrades node by node.

For a manual upgrade via Ansible:

```bash
# Update k3s_version in group_vars/all.yml, then:
ansible-playbook -i inventory.yaml site.yml \
  --tags k3s \
  --vault-password-file ~/.vault_pass

# After upgrading, verify
kubectl get nodes -o wide
```

The install script is idempotent with a different version — it upgrades in-place.

---

## Resetting the cluster (nuclear option)

```bash
# On each node, k3s provides an uninstall script:
ansible k3s_all -i inventory.yaml -m shell -a \
  "/usr/local/bin/k3s-uninstall.sh || /usr/local/bin/k3s-agent-uninstall.sh" \
  --become --vault-password-file ~/.vault_pass

# Then re-run from scratch:
ansible-playbook -i inventory.yaml site.yml \
  --vault-password-file ~/.vault_pass
```

**WARNING**: This destroys all cluster state. Longhorn volumes are removed. Ensure Velero or Longhorn backups exist before resetting.

---

## Role overview

```
roles/
├── prereqs/              # ALL nodes: apt packages, swap, sysctl, kernel modules,
│   │                     #   iSCSI, multipath, UFW firewall rules, hostname
│   ├── tasks/main.yml
│   └── handlers/main.yml
│
├── longhorn-prereqs/     # STORAGE NODES only: disk detection + format,
│   │                     #   /var/lib/longhorn mount, iSCSI initiator name
│   ├── tasks/main.yml
│   └── handlers/main.yml
│
├── k3s-server-init/      # MASTER-1 only: --cluster-init, places kube-vip
│   │                     #   in auto-deploy dir, waits for VIP, fetches token
│   ├── tasks/main.yml
│   ├── handlers/main.yml
│   └── templates/
│       └── kube-vip.yaml.j2   # templated with VIP + interface + version
│
├── k3s-server-join/      # MASTER-2 and MASTER-3: join via VIP (serial, one at a time)
│   └── tasks/main.yml
│
├── k3s-agent-join/       # WORKERS + LONGHORN NODES: join as agents
│   └── tasks/main.yml
│
└── post-install/         # Run from MASTER-1: wait for all nodes Ready,
    └── tasks/main.yml    #   apply labels + taints, fetch kubeconfig locally
```

---

## Design decisions

**Why kube-vip in the auto-deploy manifests directory?**
k3s applies everything in `/var/lib/rancher/k3s/server/manifests/` automatically at startup. By placing the kube-vip DaemonSet there before starting k3s, the VIP comes up with the first master — no manual `kubectl apply` needed, no chicken-and-egg problem.

**Why `serial: 1` for additional masters?**
etcd consensus is sensitive during node joins. Adding two new members simultaneously can cause the cluster to lose quorum briefly. Joining one at a time (serial: 1) ensures each node is committed to etcd before the next one starts joining.

**Why vault for the cluster secret?**
k3s generates a random secret if you don't specify one — but then you can't pre-know it for subsequent playbook runs. Specifying it explicitly via vault means: any node can join at any time without retrieving the token from master-1 first.

**Why taint Longhorn nodes?**
Storage nodes have dedicated I/O workloads. Without a taint, the Kubernetes scheduler may place user workloads there, creating I/O contention with Longhorn's replication. The taint ensures only Longhorn pods (which have the matching toleration) land on storage nodes.

**Why `gather_facts: true` on some plays and not others?**
`gather_facts: false` makes plays faster when you don't need OS/hardware facts. The prereqs role needs facts for package management; preflight uses `gather_facts: false` because it only does raw connectivity checks.

---

## Troubleshooting

**VIP never becomes reachable (Stage 3 hangs)**
```bash
# SSH into master-1 and check kube-vip pod
sudo k3s kubectl get pods -n kube-system | grep kube-vip
sudo k3s kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip-ds

# Check the VIP and interface in group_vars/all.yml
# Common issue: wrong vip_interface (e.g., ens18 vs eth0)
# Confirm with: ip link show on the master node
```

**Additional master fails to join (Stage 4)**
```bash
# Check the VIP is reachable from master-2:
ssh k3s-master-2 "curl -k https://10.10.30.30:6443/version"

# Check the token matches:
ssh k3s-master-1 "cat /var/lib/rancher/k3s/server/node-token"
# Must match vault_k3s_cluster_secret — or it was auto-generated (check k3s logs)
```

**Node stays NotReady**
```bash
# Check kubelet logs on the stuck node
ssh k3s-master-X "sudo journalctl -u k3s -f --no-pager | tail -50"
# Common causes: iSCSI not running, swap not disabled, sysctl not applied
```

**Ansible vault password prompt keeps appearing**
```bash
# Use a vault password file instead:
echo "your-vault-password" > ~/.vault_pass && chmod 600 ~/.vault_pass
ansible-playbook -i inventory.yaml site.yml --vault-password-file ~/.vault_pass
```

**`community.general` or `ansible.posix` module not found**
```bash
ansible-galaxy collection install ansible.posix community.general
```
