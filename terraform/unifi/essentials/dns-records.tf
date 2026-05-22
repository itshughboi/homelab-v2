# Internal DNS records — Proxmox node A records.
# These are applied via the UniFi DNS override feature (not a full DNS server).
# For cluster-level round-robin, see terraform/bind9/ for the external BIND9 approach.

resource "unifi_dns_record" "pve-srv-1" {
  name        = "pve-srv-1.hughboi.cc"
  enabled     = true
  priority    = 10
  record_type = "A"
  ttl         = 300
  value       = "10.10.10.1"
}

resource "unifi_dns_record" "pve-srv-2" {
  name        = "pve-srv-2.hughboi.cc"
  enabled     = true
  priority    = 10
  record_type = "A"
  ttl         = 300
  value       = "10.10.10.2"
}

resource "unifi_dns_record" "pve-srv-3" {
  name        = "pve-srv-3.hughboi.cc"
  enabled     = true
  priority    = 10
  record_type = "A"
  ttl         = 300
  value       = "10.10.10.3"
}

resource "unifi_dns_record" "pve-srv-4" {
  name        = "pve-srv-4.hughboi.cc"
  enabled     = true
  priority    = 10
  record_type = "A"
  ttl         = 300
  value       = "10.10.10.4"
}
