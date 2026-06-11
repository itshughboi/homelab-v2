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
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  disk {                       # VERY IMPORTANT. NEEDS TO MATCH WHAT THE TEMPLATE IS ALREADY USING. Otherwise a secondary disk will be created
    datastore_id = "local-lvm" # Change to your storage name (e.g., 'ssd-storage')
    interface    = "scsi0"     # disk that the template uses
    size         = 200         # Size in GB
  }

  network_device {
    bridge  = "vmbr1" # pve-srv-1 uses vmbr1; mini PCs use vmbr0
    vlan_id = 10
    mtu     = 1500
  }

  # eth1 — storage VLAN 40 (jumbo, MTU 9000) for NFS to TrueNAS over the east-west plane.
  # Parent bridge vmbr1 must be MTU 9000 — see docs/2-proxmox/pve/Virtual Interfaces.md.
  network_device {
    bridge  = "vmbr1"
    vlan_id = 40
    mtu     = 9000
  }

  initialization {
    datastore_id = "local-lvm" # Where the Cloud-init ISO will be stored temporarily

    dns {
      servers = ["10.10.10.8"] # Bind9 primary only — dropped 9.9.9.9/AdGuard (DNS round-robin footgun); add Bind9 secondary VIP when live. See docs/1-networking/Unifi/Networks/DNS.md
    }
    ip_config {
      ipv4 {
        # Hardcoding the IP for reliability
        address = "10.10.10.10/24"
        gateway = "10.10.10.254" # Your router/gateway IP
      }
    }

    # eth1 — VLAN 40 storage (no gateway — east-west only). Lets dock-prod mount
    # TrueNAS NFS at 10.10.40.5 over jumbo frames.
    ip_config {
      ipv4 {
        address = "10.10.40.10/24"
      }
    }

    user_account {
      username = "hughboi"
      keys     = [var.ssh_public_key]
    }
  }
}
