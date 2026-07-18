# Quickstart — condensed rebuild

The terse cheat-sheet of the **whole** Phase 0–8 rebuild. The full do→run→verify runbook with all
the caveats is **[BUILD.md](BUILD.md)** — this mirrors it, one screen per phase. Don't skip ahead.

**Have ready:** your SSH public key, a Cloudflare API token, and access to the **age private key**
backup (Vaultwarden / paper). Laptop with `terraform`/`tofu`, `ansible`, `git`, a Ventoy USB.

---

## Phase 0 — Network (UniFi, by hand) 🟢
VLANs (10 mgmt, 20 cluster, 30 k3s, 40 storage, 49 torrent, 50 IoT, 69 guest, 80 Tailscale, 81 WG);
trunk all VLANs to each node; add **every** firewall rule while default is Allow-All, then switch to
Block (keep `MGMT → MGMT ANY` — the lockout rule). DHCP **off** on 20/30/40.
→ [1-networking](1-networking/README.md)

## Phase 1 — Proxmox cluster 🟢
```sh
cd bootstrap/ventoy && ./make-isos.sh proxmox-ve_9.1-1.iso     # builds per-node auto-install ISOs
# Boot each node off the Ventoy USB → its ISO → unattended install onto 10.10.10.X
pvecm create homelab                                           # on pve-srv-1
pvecm add 10.10.10.1                                           # on pve-srv-2/3/4
cd ansible/playbooks/proxmox/network-setup && ansible-playbook main.yaml -i inventory.yaml  # bridges/VLANs, MTU 9000
cd packer/proxmox-iso-ubuntu && ./build.sh                    # build VM template 9999 (or the vm-template-refresh playbook)
```
**Verify:** `pvecm status` quorate; `qm list` shows template 9999. → [2-proxmox](2-proxmox/index.md)

## Phase 2 — Storage (TrueNAS + PBS) 🟢
TrueNAS (manual VM 105): pass the 2× Samsung SSD through, create pool **`The Archive`** (mirror),
datasets, NFS exports, IPs `.10.5` (UI) / `.40.5` (jumbo). → [4-storage/TrueNAS](4-storage/TrueNAS/README.md)
```sh
cd terraform/proxmox && terraform apply -target=proxmox_virtual_environment_vm.pbs
# pass 2× 8 TB HDD → PBS (qm set 106 --virtioN /dev/disk/by-id/...), create the zfs-backups ZFS datastore
cd ansible/playbooks/ubuntu/pbs-setup && ansible-playbook main.yaml -i inventory.yaml
```
**Verify:** PBS at `https://10.10.10.6:8007`; an NFS export mounts from a test client. → [4-storage/PBS](4-storage/PBS/README.md)

## Phase 3 — Athena (DNS / Git / Ansible) 🟢
```sh
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars                  # fill: api url, api token, ssh key
terraform apply -target=proxmox_virtual_environment_vm.athena
cd ansible/playbooks/ubuntu/setup-athena && ansible-playbook main.yaml -i inventory.yaml   # Docker, Bind9, Gitea, Semaphore
ssh hughboi@10.10.10.8 'cd /path/to/repo && ./scripts/age-setup.sh'   # SOPS age key — BACK IT UP
```
**Verify:** `dig @10.10.10.8 athena.hughboi.cc`; Gitea at `10.10.10.8:3000`. → [3-athena](3-athena/index.md)

## Phase 4 — Semaphore + hardening 🟢
Wire Semaphore (SSH key, Gitea repo, inventory) — the laptop retires here. Then harden every host:
```sh
ansible-playbook ansible/playbooks/ubuntu/hardening/harden.yaml -i <inventory>
```
**Verify:** SSH password auth disabled; `ufw status` deny-by-default. → [5-security](5-security/index.md)

## Phase 5 — Git handoff 🟢
```sh
git remote add gitea http://10.10.10.8:3000/hughboi/homelab.git && git push gitea main
```
**Verify:** repo visible in Gitea; GitHub mirror syncing.

## Phase 6 — Docker (dock-prod) 🔴 tomorrow
Provision dock-prod (Terraform), then bring up in order: **Traefik → AdGuard → CrowdSec → Vaultwarden → apps**.
→ [6-docker](6-docker/index.md)

## Phase 7 — k3s + GitOps 🔴 tomorrow
Provision the 9 k3s VMs (Terraform) → `ansible/playbooks/kubernetes/k3s/new` (kube-vip → MetalLB → Longhorn) →
sealed-secrets controller → cert-manager → Traefik → ArgoCD (`kubectl apply -f apps/kubernetes/k3s/argocd/apps/root-app.yaml`).
**Before ArgoCD:** add the `k3s → 10.10.10.8:3000` firewall allow so it can reach Gitea. → [7-k3s](7-k3s/index.md)

## Phase 8 — Backup validation
Not done until a **restore** works. → [Backup-Recovery.md](Backup-Recovery.md)

---

## Done — service URLs
| Service | URL |
| --- | --- |
| Proxmox | `https://10.10.10.1:8006` |
| PBS | `https://10.10.10.6:8007` |
| Gitea (Athena) | `http://10.10.10.8:3000` |
| Semaphore | `https://semaphore.hughboi.cc` |
| UniFi controller | `https://10.10.10.10:8443` |
| k3s | `kubectl get nodes` / Traefik ingress |
