locals {
  allow = "accept"
  deny  = "deny"

  # ── Base rule templates ────────────────────────────────────────────────────
  rules = {
    mgmt_admin = {
      proto  = "TCP"
      ports  = "22,80,443"
      source = "management"
      action = local.allow
    }

    storage_access = {
      proto  = "TCP,UDP"
      ports  = "2049,3260"
      action = local.allow
    }

    dns = {
      proto  = "TCP,UDP"
      ports  = "53"
      action = local.allow
    }
  }

  # ── Zone-based rule definitions (ordered: allows first, denies last) ───────
  _ordered_rules = flatten([
    # Management → core networks (SSH + web)
    [for dest in ["management", "cluster", "storage", "provisioning"] :
      merge(local.rules.mgmt_admin, { dest = dest })
    ],

    # Cluster internal (Corosync)
    [{
      proto  = "UDP"
      ports  = "5404-5405"
      source = "cluster"
      dest   = "cluster"
      action = local.allow
    }],

    # k3s → storage (NFS + iSCSI for Longhorn)
    [merge(local.rules.storage_access, { source = "k3s", dest = "storage" })],

    # k3s → DNS (AdGuard on management VLAN)
    [merge(local.rules.dns, { source = "k3s", dest = "management" })],

    # Provisioning VLAN (DHCP, TFTP, HTTP, DNS)
    [
      { proto = "UDP", ports = "67-68",  source = "provisioning", dest = "provisioning", action = local.allow },
      { proto = "UDP", ports = "69",     source = "provisioning", dest = "provisioning", action = local.allow },
      { proto = "TCP", ports = "80,443", source = "provisioning", dest = "provisioning", action = local.allow },
      merge(local.rules.dns, { source = "provisioning", dest = "management" }),
    ],

    # Torrent VLAN isolation — explicit deny to all internal VLANs
    [for dest in ["management", "cluster", "storage", "provisioning"] : {
      proto  = "ALL"
      ports  = "ALL"
      source = "torrent"
      dest   = dest
      action = local.deny
    }],
  ])

  # Convert to a map keyed by rule name (required for for_each).
  # Order is embedded so rule_index is stable across plan/apply.
  firewall_rules = {
    for i, r in local._ordered_rules :
    "${r.source}-to-${r.dest}-${r.ports}-${r.proto}" => merge(r, { order = 2000 + i })
  }
}
