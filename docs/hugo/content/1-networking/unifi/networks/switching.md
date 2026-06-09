---
title: "-M do = prohibit fragmentation, -s 8972 = 9000 MTU minus 28-byte IP+ICMP headers"
---

## Jumbo Frames

Required for VLAN 40 (Storage) — MTU 9000 fits ~6x more data per packet than standard MTU 1500, reducing per-packet overhead and directly increasing NFS/backup throughput between Proxmox, TrueNAS, and PBS.

**MTU must be 9000 end-to-end.** Partial support causes silent packet loss — no errors, just degraded throughput.

MTU 9000 checklist — every item must be set:
- [ ] UniFi: Settings → Switching → Jumbo Frames → **Enabled** globally (no per-network config needed)
- [ ] Proxmox slave port (e.g. `enp42s0` on pve-srv-1) → MTU 9000
- [ ] Proxmox parent bridge (`vmbr1` on pve-srv-1, `vmbr0` on pve-srv-2/3/4) → MTU 9000 — see [Virtual Interfaces.md](../../../2-proxmox/pve/Virtual%20Interfaces.md)
- [ ] Proxmox VLAN sub-interface (`.40`) → MTU 9000
- [ ] TrueNAS NIC on VLAN 40 → MTU 9000
- [ ] PBS NIC on VLAN 40 → MTU 9000

**Verify end-to-end** after any infrastructure change (only testable once TrueNAS or PBS has a `10.10.40.x` IP):

```sh
# -M do = prohibit fragmentation, -s 8972 = 9000 MTU minus 28-byte IP+ICMP headers
ping -M do -s 8972 10.10.40.x

# If it fails, step down to find the ceiling:
ping -M do -s 4000 10.10.40.x
ping -M do -s 1472 10.10.40.x   # standard 1500 MTU ceiling — if this fails, MTU is broken everywhere
```

> [!DANGER]
> Jumbo frames cannot traverse the internet — VLAN 40 is internal-only by design. If any device in the path is left at MTU 1500, oversized frames are silently dropped.

---

## Spanning Tree

Settings → Overview (Scroll to Bottom) -> Global Switch Settings

Use **RSTP** (Rapid Spanning Tree Protocol).

| Protocol | Reconvergence | Use case |
| --- | --- | --- |
| STP (802.1D) | 30–50 seconds | Legacy, avoid |
| **RSTP (802.1w)** | **1–2 seconds** | **Use this** |
| MSTP (802.1s) | 1–2 seconds | Multi-instance, overkill for this topology |

RSTP reconverges in 1–2 seconds vs 30–50 for classic STP — critical if a link flaps. MSTP adds per-VLAN spanning tree instances which aren't needed here. UniFi may auto-select RSTP but verify it's set explicitly.

---

## LACP + MLAG

> [!NOTE] Future Consideration
> LACP bonding is not currently implemented due to switch hardware limitations.
> Both switches (USW Flex) do not support LACP (802.3ad). A USW Pro, Enterprise,
> or Aggregation switch is required before this is possible.

---

## Current Workaround

Single 2.5 GbE NIC (`enp42s0` on pve-srv-1) trunking all VLANs via 802.1Q on `vmbr1`.

If a 10 GbE card is added later, it can replace the active NIC with no VLAN config changes
needed — just update the bridge slave interface.

---

## Things to Know When the Time Comes

- UniFi LACP is per-flow, not per-packet. A single stream (one NFS transfer, one VM migration)
  is capped at one link's speed — bonded throughput only appears across multiple simultaneous flows.
- The UXG Max gateway ports do not support LACP — only downstream switches do.
- Proxmox side: use `balance-xor` or `802.3ad` bond mode on the bridge.
- All switch ports in the bond must be on the same switch — cross-switch LACP (MLAG) is not
  supported on UniFi outside the Enterprise tier.
- If bonding across two different UniFi switches, use Active-Backup instead — true MLAG is
  Enterprise-tier only.

---

## Configuration Reference (when hardware supports it)

**Proxmox `/etc/network/interfaces`:**
```bash
# Physical NICs in the bond
auto enp43s0f0
iface enp43s0f0 inet manual

auto enp43s0f1
iface enp43s0f1 inet manual

# LACP bond
auto bond0
iface bond0 inet manual
    bond-slaves enp43s0f0 enp43s0f1
    bond-mode 802.3ad
    bond-miimon 100
    bond-lacp-rate fast
    bond-xmit-hash-policy layer3+4

# VLAN-aware bridge on top of the bond
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.x/24
    gateway 10.10.10.254
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
```

`layer3+4` hash policy distributes flows by src/dst IP and port — best spread for mixed
workloads like NFS + management + k3s traffic.

**UniFi switch side:**
1. Select the two ports → create a Port Profile as a LAG → set mode to LACP Active
2. That's it — UniFi handles the rest automatically

**Order of operations:** configure Proxmox side first, then plug both cables in.
Plugging in uncoordinated ports first may trigger loop detection and disable the ports.
