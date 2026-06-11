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

## DHCP — per-network (ranges in locals.tf). VLANs 20/30/40 are static-only (dhcp = false).
  dhcp_enabled = each.value.dhcp
  dhcp_start   = each.value.dhcp_start
  dhcp_stop    = each.value.dhcp_stop

  # Netboot/PXE removed — nodes install via Ventoy USB, not netboot.xyz. No DHCP boot options.
  # See docs/1-networking/Alternative Methods/Netboot/README.md (post-mortem).
}