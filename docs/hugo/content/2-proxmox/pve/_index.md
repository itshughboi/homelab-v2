---
title: "Proxmox Host Operations"
weight: 20
---

# Proxmox Host Operations

Day-to-day operation of the Proxmox hypervisor hosts. For **provisioning** (node install, VM
template, cluster formation, Terraform) see [provisioning/](../provisioning/README.md).
Per-node hardware (NICs / MACs) lives in the network inventory:
[Inventory/](../../1-networking/Unifi/Assignments/Inventory/) — not duplicated here.

| Doc | Contents |
| --- | --- |
| [Virtual Interfaces.md](Virtual%20Interfaces.md) | Bridges + VLAN sub-interfaces, MTU/jumbo frames per node |
| [Corosync.md](Corosync.md) | Cluster links/rings, quorum, no-QDevice decision |
| [cloud-init/](cloud-init/README.md) | Manual cloud-init template build + SSH setup |
| [gpu-passthrough/](gpu-passthrough/README.md) | IOMMU + PCI passthrough |
| [vm-disk-expansion/](vm-disk-expansion/README.md) | Grow a VM disk + filesystem |

---

## Notifications

- **Primary — ntfy** (`https://ntfy.hughboi.cc/homelab`): used by the Ansible playbooks and the
  PVE notification targets.
- **Email** (`alerts@hughboi.cc`): fallback only, for cases where ntfy isn't supported.

Datacenter → Notifications → add the ntfy (or SMTP) target, then update the default notification
matcher to include it.

---

## Updates

Datacenter → Updates → **Refresh**, then **Upgrade** (must be root). Or via shell:

```sh
apt update && apt dist-upgrade
```

Reboot on a kernel update. Repo setup + fleet updates are automated:
`ansible/playbooks/proxmox/cluster-update/`.

---

## Cluster

Cluster formation (Ventoy install → join → Ansible) is documented once, authoritatively, in
[provisioning/README.md → Proxmox Cluster](../provisioning/README.md#proxmox-cluster). Corosync
link/ring design and quorum live in [Corosync.md](Corosync.md).

---

## VM creation defaults

Full VM template/creation flow:
[provisioning/README.md → VM Template](../provisioning/README.md#vm-template). The host-level
hypervisor defaults that apply to any VM are documented there too, so they live in one place.

---

## Host Best Practices

1. **Repos:** set up the no-subscription repo, run updates/upgrades.
2. **Patching:** enable `unattended-upgrades`; automate a reboot cadence (e.g. every 2 weeks).
3. **Notifications:** configure ntfy (see above).
4. **TLS cert:** Datacenter → ACME → register account → apply per node.
   *(Note: not yet working reliably — cert doesn't always appear under Certificates; revisit.)*
5. **Backups:** add the PBS storage + backup jobs; set notification mode to "notification
   system" so jobs report via ntfy. Retention is managed on PBS itself.
6. **PCI passthrough:** enable IOMMU in BIOS **and** Proxmox; the VM must be **q35** (not
   i440fx). Full steps: [gpu-passthrough/](gpu-passthrough/README.md).
7. **Windows VMs:** set the correct OS type/version, upload the VirtIO drivers, add a TPM.
8. **Templates:** maintain the golden template (ID 9999) — see provisioning VM Template.
9. **Wake-on-LAN:**
   ```sh
   ethtool enp4s0 | grep "Wake-on"     # confirm a 'g' is present
   ethtool -s enp4s0 wol g
   ```
   Persist in `/etc/network/interfaces`:
   ```
   post-up /usr/sbin/ethtool -s enp4s0 wol g
   ```
   Send the magic packet with `wakeonlan <MAC>` (`brew install wakeonlan`). Magic packets don't
   cross subnets — send from a host on the target network (or via subnet routing).

### Operational hygiene

- **ZFS scrubs:** monthly — `zpool scrub <pool>` (schedule it).
- **SMART monitoring:** `apt install smartmontools`; alert on failures (see [Dependency-Map](../../Dependency-Map.md) / monitoring).
- **Snapshot before major changes** — fast, cheap, and a lifesaver.
- **PBS backup schedules** at the datacenter level for every production VM.
- **Node placement:** pin VMs to preferred nodes via resource mapping / HA groups rather than
  random placement, so you control where workloads land after a failover.
