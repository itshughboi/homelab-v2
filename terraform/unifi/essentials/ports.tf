# Create a Profile specifically for your MacBook/Provisioning
resource "unifi_port_profile" "provisioning_port" {
  name                    = "Provisioning-Only"
  native_networkconf_id    = unifi_network.production["provisioning"].id
  autoneg                 = true
  dot1x_ctrl              = "force_authorized" # Only for UXG Ports. 802.1x but should be a separate profile anyways
}

# Create a "Trunk" Profile for Proxmox Nodes 
# (This allows the nodes to see Management, Cluster, and K3s VLANs)
resource "unifi_port_profile" "management_trunk" {
  name                    = "Management-Trunk"
  native_networkconf_id    = unifi_network.production["management"].id
  tagged_networkconf_ids   = [
    unifi_network.production["cluster"].id,
    unifi_network.production["k3s"].id,
    unifi_network.production["storage"].id
  ]
  autoneg = true

  depends_on = [
    unifi_network.production
  ]
}