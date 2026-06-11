# All VLANs/networks — mirrors the production UniFi config.
#
# NOTE: UniFi is configured BY HAND in production (this workspace is break-glass reference only —
# see ../README.md). Authoritative inventory: docs/1-networking/Unifi/Assignments/MAC Reservations.md
# and docs/1-networking/Unifi/Networks/VLANs + VMs.md. Keep this in sync with those.
#
# dhcp = false on VLANs 20/30/40 — those are static-only (Corosync / cloud-init / storage NICs).

locals {
  networks = {
    "management" = {
      vlan       = 10
      subnet     = "10.10.10.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = true
      dhcp       = true
      dhcp_start = "10.10.10.100"
      dhcp_stop  = "10.10.10.200"
    }

    "cluster" = {
      vlan       = 20
      subnet     = "10.10.20.0/24"
      purpose    = "corporate"
      igmp       = true
      guard      = true
      dhcp       = false
      dhcp_start = null
      dhcp_stop  = null
    }

    "k3s" = {
      vlan       = 30
      subnet     = "10.10.30.0/24"
      purpose    = "corporate"
      igmp       = true
      guard      = true
      dhcp       = false
      dhcp_start = null
      dhcp_stop  = null
    }

    "storage" = {
      vlan       = 40
      subnet     = "10.10.40.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = true
      dhcp       = false
      dhcp_start = null
      dhcp_stop  = null
    }

    "torrent" = {
      vlan       = 49
      subnet     = "172.16.20.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = false
      dhcp       = true
      dhcp_start = "172.16.20.10"
      dhcp_stop  = "172.16.20.20"
    }

    "iot" = {
      vlan       = 50
      subnet     = "10.10.50.0/24"
      purpose    = "corporate"
      igmp       = true
      guard      = false
      dhcp       = true
      dhcp_start = "10.10.50.10"
      dhcp_stop  = "10.10.50.200"
    }

    "guest" = {
      vlan       = 69
      subnet     = "172.69.69.0/24"
      purpose    = "guest"
      igmp       = false
      guard      = false
      dhcp       = true
      dhcp_start = "172.69.69.10"
      dhcp_stop  = "172.69.69.200"
    }

    "vpn" = {
      vlan       = 80
      subnet     = "10.10.80.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = true
      dhcp       = true
      dhcp_start = "10.10.80.10"
      dhcp_stop  = "10.10.80.20"
    }

    "wireguard" = {
      vlan       = 81
      subnet     = "10.10.81.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = true
      dhcp       = true
      dhcp_start = "10.10.81.10"
      dhcp_stop  = "10.10.81.20"
    }

    # Legacy netboot VLAN — unused (provisioning moved to Ventoy USB). Kept for parity with the
    # live config until the VLAN is deleted; no PXE/boot options (netboot abandoned).
    "provisioning" = {
      vlan       = 99
      subnet     = "10.10.99.0/24"
      purpose    = "corporate"
      igmp       = false
      guard      = false
      dhcp       = true
      dhcp_start = "10.10.99.100"
      dhcp_stop  = "10.10.99.200"
    }
  }
}
