# Proxmox Virtual Interfaces

Each Proxmox node needs virtual interfaces for each VLAN it participates in.
`pve-srv-1` requires 2+ physical NICs due to the storage VLAN needing MTU 9000.

---

## Virtual Interface Table

| Virtual Interface | Target VLAN | Gateway | MTU | Notes |
| --- | --- | --- | --- | --- |
| vmbr1.10 | 10 | 10.10.10.254 | 1500 | Management — DHCP next-server: 10.10.99.99 |
| vmbr1.20 | 20 | None | 1500 | Cluster / Corosync — no gateway, QoS enabled |
| vmbr1.40 | 40 | None | 9000 | Storage — Jumbo Frames, no gateway |

> [!DANGER] Jumbo Frames on VLAN 40
> Every device on VLAN 40 (Proxmox, TrueNAS, PBS) must be configured for MTU 9000
> end-to-end: switch ports, NICs, bridges, and VMs. Partial MTU support causes
> silent packet loss. Jumbo packets cannot traverse the internet.

---

## Notes Per Interface

**vmbr1.20 (Cluster):**
- Corosync is extremely sensitive to latency
- If a NIC gets saturated with backup/storage traffic, jitter can cause a Fencing event (hard reboot)
- No gateway — completely internal
- IGMP Snooping enabled on the switch port — keeps Corosync multicast surgical, not flooded

**vmbr1.40 (Storage):**
- PBS and Longhorn can saturate the management NIC if on the same interface
- This VLAN provides physical separation of storage traffic
- No gateway — completely internal
- Jumbo Frames required end-to-end

---

## pve-srv-1 Current Bridge Config

| Name | Type | Active | VLAN Aware | Ports/Slaves | CIDR | Gateway | Comment |
| --- | --- | --- | --- | --- | --- | --- | --- |
| vmbr0 | Linux Bridge | Yes | No | — | — | — | Not used |
| vmbr1 | Linux Bridge | Yes | Yes | enp42s0 | 10.10.10.1/24 | 10.10.10.254 | VLAN-aware trunk |

→ See [`01_Hardware/01_Inventory.md`](../01_Hardware/01_Inventory.md) for full NIC list on each node.



- Each Proxmox node will need 3 virtual interfaces. `pve-srv-1` should have **2**+ physical NICs.
	1. Management / Cluster VLAN
	2. Storage VLAN - MTU 9000

| Virtual Interface | MTU  |
| ----------------- | ---- |
| vmbr0.10          | 1500 |
| vmbr0.20          | 1500 |
| vmbr0.40          | 9000 |
