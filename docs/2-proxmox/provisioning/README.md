# 3. Provisioning

Everything that goes from bare metal to running VMs: the Proxmox cluster, VM template builds, and Terraform provisioning.

---

## Prerequisites

### SSH Key

Two separate keys are used:

**Mac key** — bootstrap key, needed before Athena exists. Gets injected into every VM at Packer/Terraform build time so you can SSH directly from your laptop during initial setup.

```sh
ssh-keygen -t ed25519 -C "homelab-mac" -f ~/.ssh/homelab-mac_id_ed25519
```

Store locally for now, move to Vaultwarden once it's running. Once Semaphore is up and driving Ansible from Athena, this key mostly retires except to SSH in for troubleshooting from Mac.

A second key `homelab-athena_id_ed25519` (Athena → managed hosts) is set up later — see [3-athena/](../../3-athena/index.md).

### Clone the Repo

*Gitea*
```sh
git clone https://gitea.hughboi.cc/hughboi/homelab.git
cd homelab
```

*GitHub*
```sh
git clone https://github.hughboi.cc/itshughboi/homelab-v2.git
cd homelab-v2
```

---

## Proxmox Cluster

### Installation

Before booting each node, confirm BIOS settings:

- [ ] USB boot: **Enabled**, USB first in boot order
- [ ] Secure Boot: **OFF**

Nodes are installed via **Ventoy USB** (see [Ventoy.md](Ventoy.md)). Netboot/PXE was
abandoned — [post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md). After each node is up:

**Disable enterprise repo, enable no-subscription:**
```sh
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
apt update && apt dist-upgrade -y
```

Or via Ansible: `ansible/playbooks/proxmox/cluster-update/`

### Form the Cluster

```sh
# On pve-srv-1 (the founder node):
pvecm create homelab

# On pve-srv-2, 3, 4:
pvecm add 10.10.10.1

# Verify all nodes joined:
pvecm status  # look for: Quorate: Yes
```

### QDevice (Quorum Tie-Breaker)

With 4 nodes + 1 QDevice on Athena, you can lose 2 nodes simultaneously and stay quorate.

| Config | Total Votes | Quorum Threshold | Nodes Can Fail |
| --- | --- | --- | --- |
| 4-node bare | 4 | 3 | 1 |
| 4-node + QDevice | 5 | 3 | **2** |

> [!NOTE] Not used by choice — the cluster runs 4 nodes **without** a QDevice (quorum 3,
> tolerates 1 failure) per [Corosync](../pve/Corosync.md) and [BUILD.md](../../BUILD.md). The
> steps below are reference only, for if you later decide to add one.

To set up a QDevice (optional) after Athena is running:
```sh
# On Athena
apt install corosync-qnetd

# On any Proxmox node
pvecm qdevice setup 10.10.10.8
pvecm status   # QDevice appears in quorum info
```

> [!TIP]
> Add QDevice before adding the 4th node. Setting it up with 3 nodes first makes the 3→4 transition seamless.

### Configure Storage

In Proxmox UI or CLI:
- `local-lvm` (thin-provisioned LVM) on each node for VM disks
- Add TrueNAS NFS as a Proxmox storage backend for backup targets (PBS handles this better but both can coexist)

### API Tokens

```sh
# Terraform token (administrator)
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve terraform --privsep=0
# Copy immediately — shown once only. Store in Vaultwarden.

# Packer token (administrator)
pveum user add packer@pve
pveum aclmod / -user packer@pve -role Administrator
pveum user token add packer@pve packer --privsep=0
```

### Proxmox Best Practices

Host setup + operational best practices live in one place:
[pve/README.md → Host Best Practices](../pve/README.md#host-best-practices).

---

## VM Template (ID 9999) {#vm-template}

All VMs in this homelab clone from Template 9999 on pve-srv-1. ID 9999 puts it at the bottom of the Proxmox UI list so it never clutters the VM view.

### VM defaults (any VM, hand-built or templated)

Hypervisor knobs to set on every VM — documented here so VM creation lives in one place:

- **Machine type:** `i440fx` normally; **`q35`** if the VM needs PCI/IOMMU passthrough.
- **Disk:** enable **SSD emulation** (enables TRIM/discard so freed space is reclaimed).
- **CPU type:** `host` (exposes the full CPU feature set to the guest).
- **Memory:** ballooning **off** — avoids over-allocating host RAM across many VMs.
- **NIC:** VirtIO model, and **set MTU explicitly** (1500 for mgmt/k3s, 9000 for storage) —
  VMs inherit the bridge MTU otherwise; see [pve/Virtual Interfaces.md](../pve/Virtual%20Interfaces.md).
- **QEMU guest agent:** enabled.

There are three ways to produce the template:

### Option A — Ansible Playbook (Recommended)

Downloads the latest Ubuntu Noble cloud image, creates VM 9999, configures cloud-init, converts to template. Includes checksum verification and ntfy notification.

```sh
cd ansible/playbooks/proxmox/vm-template-refresh/
ansible-playbook main.yaml -i inventory.yaml
```

Review `main.yaml` for: `template_vmid` (9999), `storage_pool` (local-lvm), `ubuntu_release` (noble).

### Option B — Packer (Custom Packages Baked In)

Use when you want packages pre-installed (Docker, tools, agents) rather than installing them post-clone via Ansible.

```sh
cd packer/proxmox-iso-ubuntu/
cp proxmox.pkrvars.sh.example proxmox.pkrvars.sh
$EDITOR proxmox.pkrvars.sh   # fill in: PROXMOX_API_TOKEN_SECRET, SSH_PASSWORD

./build.sh            # renders Jinja2 → HCL, runs packer build (~10-15 min)
./build.sh --dry-run  # render only, skip build (review the HCL first)
```

See [`Packer.md`](Packer.md) for the full Packer build walkthrough.

### Option C — Manual (Quick One-Off)

```sh
# SSH into pve-srv-1
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create 9999 --name "ubuntu-2404-cloud" --memory 2048 --net0 virtio,bridge=vmbr0 \
  --cores 2 --ostype l26 --agent enabled=1 --onboot 0

qm importdisk 9999 noble-server-cloudimg-amd64.img local-lvm --format qcow2

disk=$(qm config 9999 | grep '^unused0:' | cut -d: -f2 | tr -d ' ')
qm set 9999 --scsihw virtio-scsi-pci --scsi0 "$disk"
qm resize 9999 scsi0 20G

qm set 9999 --boot order=scsi0 --serial0 socket --vga serial0 \
  --ide2 local-lvm:cloudinit --ipconfig0 ip=dhcp \
  --ciuser hughboi --sshkeys ~/.ssh/authorized_keys

qm template 9999
```

### Verify

Template 9999 should appear in the Proxmox UI on pve-srv-1 with a template icon (broken-square). Must exist before Terraform runs.

### Rebuild Cadence

Rebuild the template when:
- A new Ubuntu 24.04.x point release is out (update `ISO_FILE`/`ISO_CHECKSUM` in Packer, or just re-run the playbook which always fetches `current/`)
- New packages need to be baked in (e.g., `open-iscsi` for Longhorn)

Existing running VMs are not affected — Terraform only clones at `apply` time.

---

## Terraform — Provision VMs {#terraform}

All VMs are defined as code in `terraform/proxmox/`. Each service gets its own `.tf` file.

### Setup

```sh
cd terraform/proxmox/
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

Minimum required in `terraform.tfvars`:
```hcl
proxmox_api_url   = "https://10.10.10.1:8006/api2/json"
proxmox_api_token = "terraform@pve!terraform=<your-token>"
ssh_public_key    = "ssh-ed25519 AAAA... homelab-mac"
```

`terraform.tfvars` is in `.gitignore` — never commit it.

### Apply

```sh
terraform init
terraform plan   # review everything — expect athena, dock-prod, 9× k3s nodes
terraform apply  # wait 60-90s after for cloud-init to finish
```

### VM Spec Table

> This table is the source of truth for **resource sizing** (vCPU/RAM/disk), mirroring the
> Terraform definitions. The source of truth for **addressing** (IPs, MACs, VLAN, placement
> across all hosts/VMs/VIPs) is the network inventory:
> [MAC Reservations.md](../../1-networking/Unifi/Assignments/MAC%20Reservations.md). If the IP
> columns ever disagree, the inventory wins.

Per srv-2/3/4 (32 GB / 16-thread mini PCs), each hosts 1 master + 1 worker + 1 longhorn =
10 vCPU / 26 GB committed, leaving ~6 GB for the Proxmox host.

| VM | VLAN | IP | vCPU | RAM | Disk | Node |
| --- | --- | --- | --- | --- | --- | --- |
| athena | 10 | 10.10.10.8 | 4 | 8 GB | 50 GB | pve-srv-1 |
| dock-prod | 10/40 | 10.10.10.10 | 4 | 16 GB | 200 GB | pve-srv-1 |
| pbs | 10/40 | 10.10.10.6 | 2 | 8 GB | 32 GB | pve-srv-1 |
| k3s-master-1 | 30 | 10.10.30.1 | 2 | 4 GB | 50 GB | pve-srv-2 |
| k3s-master-2 | 30 | 10.10.30.2 | 2 | 4 GB | 50 GB | pve-srv-3 |
| k3s-master-3 | 30 | 10.10.30.3 | 2 | 4 GB | 50 GB | pve-srv-4 |
| k3s-worker-1 | 30/40 | 10.10.30.11 | 6 | 16 GB | 50 GB | pve-srv-2 |
| k3s-worker-2 | 30/40 | 10.10.30.12 | 6 | 16 GB | 50 GB | pve-srv-3 |
| k3s-worker-3 | 30/40 | 10.10.30.13 | 6 | 16 GB | 50 GB | pve-srv-4 |
| k3s-longhorn-1 | 30/40 | 10.10.30.51 | 2 | 6 GB | 300 GB | pve-srv-2 |
| k3s-longhorn-2 | 30/40 | 10.10.30.52 | 2 | 6 GB | 300 GB | pve-srv-3 |
| k3s-longhorn-3 | 30/40 | 10.10.30.53 | 2 | 6 GB | 300 GB | pve-srv-4 |

> **Dual-homed VLANs:** `10/40` and `30/40` = a primary NIC plus a VLAN-40 storage NIC (MTU 9000).
> PBS's 32 GB is the OS disk only — its backup data lives on 2× passed-through 8 TB HDDs.
> **TrueNAS is a manual appliance** (not Terraform), so it's deliberately not in this table — see
> [4-storage](../../4-storage/index.md).

### State Backend

Default is local state. To use the Gitea HTTP backend (recommended):
```sh
export TF_HTTP_PASSWORD=<gitea-api-token>
terraform init -migrate-state
```

See `terraform/proxmox/backend.tf` for config.

### Day-2 VM Operations

**Add a new VM:**
1. Create a new `.tf` file (copy `athena.tf` as template)
2. `terraform plan` to preview
3. `terraform apply` — Proxmox clones template 9999 and boots

**Resize a disk:**
```sh
# Change size in .tf file, then:
terraform apply
# Grow partition inside the VM:
ssh hughboi@<vm-ip>
sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1
```

**Destroy a single VM:**
```sh
terraform destroy -target=proxmox_virtual_environment_vm.k3s_master[0]
```

> [!WARNING]
> **Never edit Terraform-managed VMs in the Proxmox GUI.** GUI changes cause state drift and `terraform apply` will revert them. For one-off changes, use `terraform import` first, then manage via code.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Node SSH unreachable | Serial console: `screen /dev/cu.usbserial-XXXX 115200` |
| Cluster lost quorum | `pvecm status` → check QDevice is reachable on Athena (`10.10.10.8`) |
| Corosync fencing loop | Stop the problem node; check VLAN 20 for NIC saturation or QoS misconfiguration |
