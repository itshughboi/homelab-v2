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
    size         = 50
  }

  network_device {
    bridge = "vmbr0"
    vlan_id = 3
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["9.9.9.9", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        # Hardcode IPs for predictability
        address = "10.10.30.${count.index + 11}/24"
        gateway = "10.10.30.254"
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}