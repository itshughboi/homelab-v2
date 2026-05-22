# LACP / MLAG

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
