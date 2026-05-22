# DHCP reservations — pins MAC addresses to static IPs for Proxmox nodes.
# These are the physical server NICs, not the VM interfaces.
#
# Note: MACs here are the management NICs used for DHCP leases.
# The PXE boot NICs (different ports on the same NIC controllers) are
# mapped in bootstrap/netbootxyz/config/local.ipxe — consecutive MACs
# on multi-port adapters explain the slight difference.

locals {
  pve_nodes = {
    pve-srv-1 = { mac = "04:7c:16:87:65:66", ip = "10.10.10.1" }
    pve-srv-2 = { mac = "c8:ff:bf:00:80:7c", ip = "10.10.10.2" }
    pve-srv-3 = { mac = "1c:83:41:40:ff:0b", ip = "10.10.10.3" }
    pve-srv-4 = { mac = "c8:ff:bf:03:f3:50", ip = "10.10.10.4" }
  }
}

resource "unifi_client" "pve" {
  for_each = local.pve_nodes

  mac          = each.value.mac
  name         = each.key
  display_name = each.key

  fixed_ip         = each.value.ip
  local_dns_record = each.key

  network_id = unifi_network.production["management"].id

  skip_forget_on_destroy = true
}
