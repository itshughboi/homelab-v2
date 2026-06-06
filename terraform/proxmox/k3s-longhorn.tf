locals {
  k3s_longhorn_count = 3
}

resource "proxmox_virtual_environment_vm" "k3s_longhorn" {
  count       = local.k3s_longhorn_count
  name        = "k3s-longhorn-${count.index + 1}"
  description = "k3s Longhorn Storage"
  tags        = ["k3s", "longhorn", "cluster"]
  node_name   = var.proxmox_nodes_k3s[count.index % length(var.proxmox_nodes_k3s)]
  vm_id       = 621 + count.index
  started     = true

  clone {
    vm_id = 9999   # Pre-existing VM template
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 300 # increased space for longhorn
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 30
    mtu     = 1500
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["10.10.10.8", "10.10.10.10", "9.9.9.9"]
    }

    ip_config {
      ipv4 {
        # Hardcode IPs for predictability
        address = "10.10.30.${count.index + 51}/24"
        gateway = "10.10.30.254"
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}