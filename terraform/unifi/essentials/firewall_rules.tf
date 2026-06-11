# ── NOT expressed here — the legacy unifi provider can't cleanly mirror the ZONE-BASED prod
#    firewall. Configure these BY HAND per docs/1-networking/Unifi/Firewall/Rules.md (the live
#    source of truth). This file only covers the inter-zone ALLOW matrix (real-src -> real-dst):
#      - MGMT -> MGMT ANY (anti-lockout; intra-VLAN — zone-firewall only, no LAN_IN equivalent)
#      - ANY -> {MGMT, CLUSTER, k3s, STORAGE, IoT, GUEST, VPN, WireGuard} DENY  (src = "any")
#      - k3s -> MGMT DENY (lateral-movement block; must sit below the host exceptions)
#      - host allows: k3s -> 10.10.10.8:3000 (ArgoCD<->Gitea), k3s -> 10.10.10.8:53 (Bind9),
#        torrent VM -> 10.10.40.5:2049 (NFS), WAN -> Gateway:51820 (WireGuard tunnel)
#      - groups/egress: *->RFC1918 DENY (needs an IP group), IoT/Guest/Torrent -> WAN
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

    # Management → remaining zones (admin: SSH + web)
    [for dest in ["k3s", "torrent", "vpn", "iot"] :
      merge(local.rules.mgmt_admin, { dest = dest })
    ],

    # k3s → IoT (Home Assistant device control — TODO scope to the HA IP once deployed; see Rules.md)
    [{ proto = "ALL", ports = "ALL", source = "k3s", dest = "iot", action = local.allow }],

    # Tailscale VPN → trusted zones (scoped admin / cluster / storage access)
    [for dest in ["management", "k3s", "storage"] :
      merge(local.rules.mgmt_admin, { source = "vpn", dest = dest })
    ],

    # WireGuard VPN → trusted zones (same scoped access, a different tunnel)
    [for dest in ["management", "k3s", "storage"] :
      merge(local.rules.mgmt_admin, { source = "wireguard", dest = dest })
    ],

    # Torrent VLAN isolation — explicit deny to all internal VLANs
    [for dest in ["management", "cluster", "k3s", "storage", "iot", "vpn", "wireguard", "provisioning"] : {
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
