locals {
  networks = {
    "management" = {
      vlan    = 10
      subnet  = "10.10.10.0/24"
      purpose = "corporate"
      igmp    = false
      guard   = true
      dhcp    = false
    }

    "cluster" = {
      vlan    = 20
      subnet  = "10.10.20.0/24"
      purpose = "corporate"
      igmp    = true
      guard   = true
      dhcp    = false
    }

    "k3s" = {
      vlan    = 30
      subnet  = "10.10.30.0/24"
      purpose = "corporate"
      igmp    = true
      guard   = true
      dhcp    = false
    }

    "storage" = {
      vlan    = 40
      subnet  = "10.10.40.0/24"
      purpose = "corporate"
      igmp    = false
      guard   = true
      dhcp    = false
    }

    "torrent" = {
      vlan    = 49
      subnet  = "172.16.20.0/24"
      purpose = "corporate"
      igmp    = false
      guard   = false
      dhcp    = true
    }

    "vpn" = {
      vlan    = 80
      subnet  = "10.10.80.0/24"
      purpose = "corporate"
      igmp    = false
      guard   = true
      dhcp    = true
    }

    "provisioning" = {
      vlan    = 99
      subnet  = "10.10.99.0/24"
      purpose = "corporate"
      igmp    = false
      guard   = false
      dhcp    = true
    }
  }
}
