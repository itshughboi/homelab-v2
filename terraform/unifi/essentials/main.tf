terraform {
  required_providers {
    unifi = {
      source = "ubiquiti-community/unifi"
      version = "~> 0.41.12"
    }
  }
}

### Provider options from official documentation; https://registry.terraform.io/providers/ubiquiti-community/unifi/latest/docs

provider "unifi" {
  api_key        = var.api_key != "" ? var.api_key : null         #Used with cloud controller. This rule says use API if available, else use username/password
  username       = var.api_key == "" ? var.unifi_username : null           # Controller username. Rule says: Only use username if NO API key
  password       = var.api_key == "" ? var.unifi_password : null          # Controller password. Rule says: Only use password if NO API key
  
  api_url        = var.api_url                   # your UniFi Controller URL
  site           = var.unifi_site                # only change if not default site
  allow_insecure = var.allow_insecure            # needs to be true if self-signed SSL

}


resource "unifi_network" "production" {
  for_each = local.networks

  name    = each.key
  purpose = each.value.purpose
  vlan_id = each.value.vlan
  subnet  = each.value.subnet


## Feature mapping
  igmp_snooping = each.value.igmp
  dhcp_guarded  = each.value.guard

## DHCP Range
  dhcp_enabled = each.key == "provisioning"     #  dhcp_enabled = true

  dhcp_start = each.key == "provisioning" ? "10.10.99.100" : null     #  dhcp_start   = cidrhost(each.value.subnet, 100)
  dhcp_stop  = each.key == "provisioning" ? "10.10.99.200" : null     #  dhcp_stop    = cidrhost(each.value.subnet, 200)



## PXE: only the provisioning VLAN boots via netboot.xyz
  dhcpd_boot_enabled  = each.key == "provisioning"
  dhcpd_boot_server   = each.key == "provisioning" ? "10.10.99.100" : null
  dhcpd_boot_filename = each.key == "provisioning" ? "netboot.xyz.kpxe" : null



### PXE Boot option 66 & 67
  dynamic "dhcp_options" {
    for_each = each.key == "provisioning" ? [1] : []  # only applies to network "provisioning"
    content {
      option = 66  # TFTP server for PXE
      value  = "10.10.99.100"  # IP of your NetbootXYZ host
    }
    # Optionally add 67: bootfile name, etc.
  }
}