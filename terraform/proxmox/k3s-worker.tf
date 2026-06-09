locals {
  k3s_worker_count = 3
}

resource "proxmox_virtual_environment_vm" "k3s_worker" {
  count       = local.k3s_worker_count
  name        = "k3s-worker-${count.index + 1}"
  description = "k3s Worker Node"
  tags        = ["k3s", "worker", "cluster"]
  node_name   = var.proxmox_nodes_k3s[count.index % length(var.proxmox_nodes_k3s)]
  vm_id       = 611 + count.index
  started     = true

  clone {
    vm_id = 9999 # Pre-existing VM template
    full  = true
  }

  cpu {
    cores = 6
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
  }

  # eth0 — k3s workload VLAN 30
  network_device {
    bridge  = "vmbr0"
    vlan_id = 30
    mtu     = 1500
  }

  # eth1 — storage VLAN 40 (dual-homed). Longhorn replica/volume traffic should use this NIC,
  # not VLAN 30. MTU 9000 — must match the switch + Longhorn's `storage-network` setting.
  network_device {
    bridge  = "vmbr0"
    vlan_id = 40
    mtu     = 9000
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["10.10.10.8", "10.10.10.10", "9.9.9.9"]
    }

    # eth0 — VLAN 30
    ip_config {
      ipv4 {
        # Hardcode IPs for predictability
        address = "10.10.30.${count.index + 11}/24"
        gateway = "10.10.30.254"
      }
    }

    # eth1 — VLAN 40 storage (no gateway — east-west only)
    ip_config {
      ipv4 {
        address = "10.10.40.${count.index + 11}/24"
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}