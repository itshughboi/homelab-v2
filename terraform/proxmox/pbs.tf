resource "proxmox_virtual_environment_vm" "pbs" {
  name        = "pbs"
  description = "Proxmox Backup Server — dual-homed VLAN 10 (mgmt) + VLAN 40 (storage)"
  tags        = ["infrastructure", "storage"]
  node_name   = var.proxmox_master
  vm_id       = 106
  started     = true

  clone {
    vm_id = 9999
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  # OS disk only — data lives on passed-through drives (see note below)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
  }

  # NIC 0 — VLAN 10 management
  # Proxmox backup jobs from hypervisor hosts arrive here (hypervisors have no VLAN 40 IP)
  network_device {
    bridge  = "vmbr1"
    vlan_id = 10
    mtu     = 1500
  }

  # NIC 1 — VLAN 40 storage east-west.
  # NOTE: likely vestigial. PBS now uses a LOCAL ZFS datastore (passed-through disks) and
  # backs up OFFSITE to the Synology (VLAN 10 / Tailscale) — there is no PBS↔TrueNAS NFS
  # datastore anymore. This NIC can probably be removed. Kept until confirmed.
  network_device {
    bridge  = "vmbr1"
    vlan_id = 40
    mtu     = 9000
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["10.10.10.8", "10.10.10.10", "9.9.9.9"]
    }

    # NIC 0 — VLAN 10 management (gateway here, not on storage NIC)
    ip_config {
      ipv4 {
        address = "10.10.10.6/24"
        gateway = "10.10.10.254"
      }
    }

    # NIC 1 — VLAN 40 storage (no gateway — east-west only)
    ip_config {
      ipv4 {
        address = "10.10.40.6/24"
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}

# ── Drive passthrough — PBS datastore (2× 8 TB HDD) ─────────────────────────────
# PBS owns its disks directly (no TrueNAS NFS). The two 8 TB HDDs are passed through
# from pve-srv-1. Terraform's proxmox provider does not support raw device passthrough,
# so after `terraform apply` run this on the Proxmox host shell (pve-srv-1):
#
#   ls -l /dev/disk/by-id/   # confirm the IDs still match before running
#
#   qm set 106 --virtio1 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15MQS4
#   qm set 106 --virtio2 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15JMEQ
#
# (Use by-id, never /dev/sdX — those names are not stable across reboots.)
#
# Then boot the VM and create the ZFS datastore *inside PBS*:
#   Administration → Storage / Disks → ZFS → Create ZFS
#   - select both virtio disks, RAID level "mirror"
#   - check "Add as Datastore"
#   - Compression: LZ4
#
# Full runbook: docs/4-storage/PBS/README.md
