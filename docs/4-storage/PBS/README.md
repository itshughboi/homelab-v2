# Proxmox Backup Server (PBS)

PBS runs as a **VM** (ID 106) on pve-srv-1 — *not* an LXC. It **owns its disks directly**:
two 8 TB HDDs are passed through from the host and PBS builds a **local ZFS** datastore on them
(PBS prefers to own its storage rather than back onto NFS). Backups then go **offsite to the
Synology**. There is no TrueNAS NFS datastore.

- Provisioned by Terraform: [`terraform/proxmox/pbs.tf`](../../../terraform/proxmox/pbs.tf) — VM 106, dual-homed `10.10.10.6` (mgmt) / `10.10.40.6` (storage).
- Configured by Ansible: `ansible/playbooks/ubuntu/pbs-setup/` — installs `proxmox-backup-server`, opens 8007, creates the `backup@pam` user.

> [!NOTE] Why a VM with passed-through disks (not an LXC, not NFS)
> PBS wants to own its datastore for integrity (its own checksums + chunk store). A VM with
> raw-disk passthrough gives it that; an LXC or an NFS-backed datastore does not. Offsite
> resilience comes from replicating finished backups to the Synology, not from where the
> primary datastore lives.

---

## 1. Pass through the 2× 8 TB HDDs (on the Proxmox host)

Terraform creates the VM + 32 GB OS disk; raw-disk passthrough is a manual `qm set` step:

```sh
ls -l /dev/disk/by-id/      # confirm IDs before running — use by-id, never /dev/sdX

qm set 106 --virtio1 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15MQS4
qm set 106 --virtio2 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15JMEQ
```

## 2. Create the local ZFS datastore (inside PBS)

`Administration → Storage / Disks → ZFS → Create ZFS`:
- select both virtio disks, RAID level **mirror** (1-disk fault tolerance)
- check **Add as Datastore**
- **Compression: LZ4**

## 3. Repos + updates

`Administration → Repositories` → disable enterprise, add **No-Subscription** →
`Administration → Updates` → Refresh, then Upgrade. (Or it's handled by the `pbs-setup` playbook.)

Optional — remove the subscription nag (community helper script):
```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pbs-install.sh)"
```

## 4. Notifications — ntfy

`Configuration → Notifications` → add the **ntfy** target (`https://ntfy.hughboi.cc/homelab`),
then enable it on the default notification matcher. Email (`alerts@hughboi.cc`) is the fallback
only where ntfy isn't supported. *(Gotify is retired.)*

## 5. Add PBS to Proxmox VE

`Datacenter → Storage → Add → Proxmox Backup Server`:

```
ID:          pbs
Server:      10.10.10.6        ← management IP (see note)
Username:    backup@pam        ← scoped user, NOT root
Datastore:   <the ZFS datastore name>
Fingerprint: PBS → Datastore → Summary → Show Connect Info
```

> [!NOTE] Use the management IP
> Proxmox backup jobs originate from the hypervisor host, which only has a VLAN 10 IP — so the
> server address must be `10.10.10.6` (mgmt). Backup data flows over VLAN 10 at MTU 1500.

> [!IMPORTANT] User + encryption
> Use a dedicated `backup@pam` user scoped to the datastore — not root. The `pbs-setup` playbook
> creates it. Datastore encryption *should* be on; if you hit restore issues with it enabled,
> that's a known wrinkle to work through before relying on it.

## 6. Backup schedule + jobs

`Datacenter → Backup → Add`: all VMs, **snapshot** mode (no downtime), email/ntfy on completion.

> **Retention is configured on PBS only — not in Proxmox VE.** Set it once on the datastore.

Datastore jobs (on PBS):

| Job | Schedule |
| --- | --- |
| Prune | daily 21:30 |
| GC | daily 08:45 |
| Verify | daily, skip already-verified, re-verify after 30 days (verify new snapshots: yes) |

## 7. Offsite to Synology

Backups replicate offsite to the Synology, which stays on VLAN 10 (Management) — it's temporary
and going offsite, so **don't move it to VLAN 40**.

- Install the **Tailscale** package on the Synology (Package Center) *before* it leaves, and join
  the tailnet. PBS then targets the Synology's **Tailscale IP** (`100.x.x.x`), so jobs keep
  working regardless of where it physically lives.
- Do the **initial full sync while the Synology is still onsite** — a first full over a remote
  uplink is painfully slow.

Mount + datastore (on PBS):
```sh
mkdir /mnt/synology
# /etc/fstab — Synology NFS export
<synology-tailscale-ip>:/volume1/PBS-Replica /mnt/synology nfs vers=3,nouser,atime,auto,retrans=2,rw,dev,exec 0 0
```
Then add a datastore with **Backing Path** `/mnt/synology` (sync/replicate finished backups here).

## 8. Homepage widget

The widget user must be in the **PAM** realm (not PVE):
```sh
proxmox-backup-manager user create homepage@pam --enable 1
```
Widget config: https://gethomepage.dev/widgets/services/proxmoxbackupserver/

---

## Testing restores (monthly)

> A backup you've never restored from is not a backup — it's a hope.

1. Restore a non-critical VM to a new temporary VM ID from PBS.
2. Confirm it boots and works.
3. Delete the test VM.
