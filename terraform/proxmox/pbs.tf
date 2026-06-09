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

  # NIC 1 — VLAN 40 storage east-west
  # PBS ↔ TrueNAS NFS datastore, replication. MTU 9000 — must match switch + TrueNAS NIC.
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

# ── Drive passthrough ──────────────────────────────────────────────────────────
# Terraform's proxmox provider does not support raw device passthrough.
# After `terraform apply`, run on the Proxmox host shell (pve-srv-1):
#
#   ls -l /dev/disk/by-id/   # find your drive IDs
#
#   qm set 106 --virtio1 /dev/disk/by-id/<YOUR_DISK_ID_1>
#   qm set 106 --virtio2 /dev/disk/by-id/<YOUR_DISK_ID_2>
#
# Add as many drives as needed. Then boot the VM and create a ZFS pool inside PBS:
#   Administration → Storage / Disks → ZFS → Create ZFS
#   Check "Add as Data Store" and set Compression to LZ4.
