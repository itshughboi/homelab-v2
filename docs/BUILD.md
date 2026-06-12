# Build Guide — bare metal → running homelab

The "wipe everything and rebuild, in order" runbook. Each phase: **do → run → verify**. Follow
top to bottom; don't skip ahead (dependencies break).

> **Tonight (you said):** Phases 0–5. **Phases 6–7 (Docker, k3s) are tomorrow** and are marked.
> Detailed per-area docs are linked at each step; this page is the linear path.

**Before you start — have these ready:**
- Your SSH public key(s), a Cloudflare API token (for later TLS), and access to Vaultwarden / the
  paper backup of your **age private key** (for SOPS).
- A laptop with: `terraform`/`tofu`, `ansible`, `git`, and a Ventoy USB.

---

## Phase 0 — Network (UniFi, manual) 🟢 tonight

UniFi is configured **by hand in the UI** (the `terraform/unifi/` workspace is sunset reference).
Full detail: [1-networking/](1-networking/README.md).

**Do:**
1. VLANs: 10 mgmt, 20 cluster, 30 k3s, 40 storage, 49 torrent, 50 IoT, 80/81 VPN — see [VLANs](1-networking/Unifi/Networks/VLANs%20+%20VMs.md). DHCP **off** on 20/30/40.
2. Switch ports: trunk all VLANs to each Proxmox node — [Switch ports](1-networking/Unifi/Assignments/Switch_Port_Assignments.md).
3. Firewall: add **every rule** from [Firewall/Rules.md](1-networking/Unifi/Firewall/Rules.md) **while default is Allow All**, then enable Block. ⚠️ The `MGMT → MGMT ANY` rule is non-negotiable (the June-2026 lockout).
4. Security baseline: IPS, region block, etc. — [Security/](1-networking/Unifi/Security/README.md).

**Verify:** `ping 10.10.10.254` from a mgmt client; an IoT/guest device **cannot** reach `10.10.10.10`.

---

## Phase 1 — Proxmox cluster 🟢 tonight

Full detail: [2-proxmox/provisioning/](2-proxmox/provisioning/README.md).

**Do/Run — install the nodes (Ventoy auto-install):**
```sh
# On an existing amd64 Proxmox host (or your first node once up):
cd bootstrap/ventoy
./make-isos.sh proxmox-ve_9.1-1.iso          # builds pve-srv-X-auto.iso from the answer TOMLs
# Copy out/*.iso to the Ventoy USB. BIOS: USB-boot first, Secure Boot off.
# Boot each node → pick its ISO → unattended install onto 10.10.10.X. Plug into its trunk port.
```
**Run — form the cluster (manual; no join playbook):**
```sh
# on pve-srv-1 (founder):
pvecm create homelab
# on pve-srv-2, 3, 4:
pvecm add 10.10.10.1
pvecm status          # Quorate: Yes
```
> No QDevice (by choice): 4 nodes tolerate 1 failure. [Corosync](2-proxmox/pve/Corosync.md).

**Run — node network (bridges + VLAN sub-interfaces):**
```sh
cd ansible/playbooks/proxmox/network-setup
ansible-playbook main.yaml -i inventory.yaml   # creates vmbrX.20 / .40 (MTU 9000)
```

**Run — VM template 9999** (Terraform clones this; build it first, from your laptop):
```sh
cd packer/proxmox-iso-ubuntu && ./build.sh     # OR the vm-template-refresh playbook
```

**Verify:** `pvecm status` quorate; `qm list` shows template 9999 on pve-srv-1.

---

## Phase 2 — Storage (TrueNAS + PBS) 🟢 tonight

Full detail: [4-storage/](4-storage/index.md).

**Do — TrueNAS** (VM with disk passthrough): pass the 2× Samsung SSDs through, create the ZFS
pool, set up NFS exports, and use a **`br0` bridge** for the IP — [TrueNAS](4-storage/TrueNAS/README.md).

**Run — PBS** (VM, owns its disks):
```sh
cd terraform/proxmox && terraform apply -target=proxmox_virtual_environment_vm.pbs
# then on pve-srv-1, pass through the 2× 8TB HDDs (qm set 106 --virtio1 /dev/disk/by-id/...)
#   see terraform/proxmox/pbs.tf for the exact IDs
# inside PBS: create the mirror ZFS datastore, then:
cd ansible/playbooks/ubuntu/pbs-setup && ansible-playbook main.yaml -i inventory.yaml
```

**Verify:** PBS UI at `https://10.10.10.6:8007`; an NFS export mounts from a test client.

---

## Phase 3 — Athena (management plane: DNS, Git, Ansible) 🟢 tonight

Athena is the control center. Full detail: [3-athena/](3-athena/index.md).

**Run — provision the VM (from laptop):**
```sh
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars   # API token, ssh key
terraform apply -target=proxmox_virtual_environment_vm.athena
```
**Run — install the management stack (from laptop, last laptop-driven step):**
```sh
cd ansible/playbooks/ubuntu/setup-athena
ansible-playbook main.yaml -i inventory.yaml          # Docker, Bind9, Gitea, Semaphore
```
**Run — secrets (on Athena, NOT the laptop):**
```sh
ssh hughboi@10.10.10.8
cd /path/to/repo && ./scripts/age-setup.sh            # generates the age key, patches .sops.yaml
#  → BACK UP the private key (you have paper + cloud — good)
git add .sops.yaml && git commit -m "chore: sops age public key" && git push
```
> [!IMPORTANT] **Generate this key here and keep it safe.** Losing it makes every SOPS secret
> unrecoverable. See [8-gitops/Secrets_SOPS.md](8-gitops/Secrets_SOPS.md).

**Verify:** `dig @10.10.10.8 athena.hughboi.cc`; Gitea reachable at `10.10.10.8:3000`.

---

## Phase 4 — Hand off to Semaphore + final security 🟢 tonight

**Do:** set up Semaphore (`https://semaphore.hughboi.cc` once Traefik is up — tomorrow; until then
by IP): add the SSH key, the Gitea repo, the inventory path — [Semaphore setup](3-athena/index.md#semaphore-setup).
From here, Ansible runs from Semaphore — **the laptop retires.**

**Run — harden every host:**
```sh
# via Semaphore or laptop:
ansible-playbook ansible/playbooks/ubuntu/hardening/harden.yaml -i <inventory>
```
**Verify:** SSH password auth disabled; `ufw status` deny-by-default; run [security routine checks](5-security/index.md#routine-security-checks-semaphore-schedule).

---

## Phase 5 — Git handoff 🟢 tonight

Push the repo to your Athena Gitea; GitHub stays as the offsite mirror.
```sh
git remote add gitea http://10.10.10.8:3000/hughboi/homelab.git
git push gitea main
```
**Run — migrate Terraform state off the laptop** (now that Gitea exists):
```sh
# Gitea UI: Settings → Applications → generate an access token
export TF_HTTP_PASSWORD=<gitea-token>
# uncomment the "Option B" backend block in terraform/proxmox/backend.tf, then:
cd terraform/proxmox && terraform init -migrate-state
rm -f terraform.tfstate terraform.tfstate.backup     # local copies retired
```
**Verify:** repo visible in Gitea; GitHub mirror syncing; `terraform plan` works against the
Gitea-backed state (and the state package shows in Gitea → Packages).

---

## Phase 6 — Docker services 🔴 tomorrow

dock-prod stack (Traefik → AdGuard → CrowdSec → Vaultwarden → apps). Order + commands:
[6-docker/](6-docker/index.md). **Work the [Hardening TODO](6-docker/index.md#hardening-todo-from-the-per-app-audit) as you go.**

## Phase 7 — k3s + GitOps 🔴 tomorrow

k3s VMs (Terraform) → `kubernetes/k3s/new` → kube-vip → MetalLB → Longhorn → sealed-secrets
controller → cert-manager → Traefik → ArgoCD. Full sequence: [7-k3s/](7-k3s/index.md).
**Before ArgoCD:** add the `k3s → 10.10.10.8:3000` firewall allow so ArgoCD can reach Gitea.
(Secrets are imperative today — there's no sealed-secrets key to restore yet; that step applies
only after the planned Sealed Secrets migration.)

## Phase 8 — Backup validation (ongoing)

Don't call it done until a restore works: [Backup-Recovery.md](Backup-Recovery.md).

---

## Open items to hit as you reach them
Tracked in their home docs: [Docker hardening](6-docker/index.md#hardening-todo-from-the-per-app-audit) ·
[securityContext/PSA](5-security/index.md#pod-security-securitycontext--psa) ·
[Sealed Secrets migration](8-gitops/index.md#secrets-in-kubernetes) ·
[dead-man's switch](7-k3s/Monitoring.md#dead-mans-switch) · [backup tests](Backup-Recovery.md) ·
Velero S3 target ([7-k3s](7-k3s/index.md#platform-components)). **k3s/Docker items don't apply
tonight.**
