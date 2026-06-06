resource "proxmox_virtual_environment_vm" "dock-prod" {
  name        = "dock-prod" # Case sensitive
  description = "Docker"
  tags        = ["docker"]
  node_name   = var.proxmox_master
  vm_id       = 110

  #agent       = 1 # QEMU option for speed + proxmox console viewing. I think this syntax is wrong

# Ensure the VM starts after creation
  started = true

#  lifecycle {
#    prevent_destroy = true
#}

  clone {
    vm_id = 9999 # Pre-existing VM template made with Packer we are cloning from
    full = true
  }

  cpu {
    cores = 4
    type  = "host" 
  }

  memory {
    dedicated = 16384
  }

  disk {  # VERY IMPORTANT. NEEDS TO MATCH WHAT THE TEMPLATE IS ALREADY USING. Otherwise a secondary disk will be created
    datastore_id = "local-lvm" # Change to your storage name (e.g., 'ssd-storage')
    interface    = "scsi0" # disk that the template uses
    size         = 200 # Size in GB
  }

  network_device {
    bridge  = "vmbr1" # pve-srv-1 uses vmbr1; mini PCs use vmbr0
    vlan_id = 10
    mtu     = 1500
  }

  initialization {
    datastore_id = "local-lvm" # Where the Cloud-init ISO will be stored temporarily

    dns {
      servers = ["10.10.10.8", "10.10.10.10", "9.9.9.9"]
    }
    ip_config {
      ipv4 {
        # Hardcoding the IP for reliability
        address = "10.10.10.10/24"
        gateway = "10.10.10.254"    # Your router/gateway IP
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}
