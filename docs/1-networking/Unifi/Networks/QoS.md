## IGMP Snooping

Settings → Switching → IGMP Snooping (or per-network Advanced settings)

**Enable per-VLAN.** Prevents multicast traffic from flooding every switch port — only forwards to ports that have requested membership.

Without it: Chromecast, Apple TV, Sonos, and other multicast-heavy devices send traffic to every port on the VLAN.

Enable on:
- Management (10)
- k3s (30)
- IoT (50)

---

## Jumbo Frames (MTU 9000)

Jumbo frames are enabled globally on the switch, but only take effect on VLANs where MTU 9000 is configured. Devices on other VLANs are unaffected.

MTU 9000 fits ~6x more data per packet than standard MTU 1500 — fewer packets means less per-packet overhead (headers, interrupts, CPU cycles), which directly increases NFS/backup throughput between Proxmox, TrueNAS, and PBS.

- **Enable on switch:** Devices → [USW Flex Mini] → Settings → Disable Global Switch Settings → Jumbo Frames Enabled
- **Set per-network:** Settings → Networks → Storage (VLAN 40) → MTU → 9000

**Verify end-to-end after any infrastructure change** — partial MTU support causes silent packet loss with no errors, just degraded throughput. Only testable once TrueNAS or PBS has a `10.10.40.x` IP.

```sh
# Run from a storage node targeting TrueNAS (or between any two VLAN 40 hosts)
# -M do = prohibit fragmentation
# -s 8972 = 9000 MTU minus 28-byte IP+ICMP headers
ping -M do -s 8972 10.10.40.x

# If it fails, step down to find the ceiling:
ping -M do -s 4000 10.10.40.x
ping -M do -s 1472 10.10.40.x   # standard 1500 MTU ceiling — if this fails, MTU is broken everywhere
```

MTU 9000 checklist — every item must be set, partial is broken:
- [ ] UniFi switch: Devices → [USW Flex Mini] → Settings → Disable Global Switch Settings → Jumbo Frames Enabled
- [ ] UniFi network: Settings → Networks → Storage (VLAN 40) → MTU → 9000
- [ ] Proxmox slave port (e.g. enp42s0 for pve-srv-1)
- [ ] Proxmox parent bridge (`vmbr1` on pve-srv-1, `vmbr0` on pve-srv-2/3/4) → MTU 9000
	- [ ] See [Virtual Interfaces.md](../../Proxmox/Virtual%20Interfaces.md)
- [ ] Proxmox VLAN sub-interface (`.40`) → MTU 9000
- [ ] TrueNAS NIC on VLAN 40 → MTU 9000
- [ ] PBS NIC on VLAN 40 → MTU 9000

---

## QoS

> [!IMPORTANT] **Prerequisite — enable Smart Queue Management (SQM) first**
> QoS policies cannot be saved until SQM is active on the WAN interface.
> Settings → Internet → [WAN] → Advanced → Manual → Smart Queues → enable → set Downrate and Uprate to your actual ISP speeds → Save.
> SQM also prevents bufferbloat independently of QoS policies — it's worth enabling regardless.

Settings → Overview → Policy Based Routing → Create Policy

| VLAN                                    | Priority   | Behavior             | Reason                                         |
| --------------------------------------- | ---------- | -------------------- | ---------------------------------------------- |
| Management (10)                         | Highest    | Prioritize           | Admin SSH must never lag                       |
| Tailscale VPN (80) / WireGuard VPN (81) | High       | Prioritize           | Remote access                                  |
| k3s (30)                                | Medium     | Prioritize           | Workload traffic                               |
| IoT (50)                                | Medium-low | Prioritize           | Smart home, not latency-sensitive              |
| Torrent (49)                            | Lowest     | Prioritize and Limit | Cap upload so it can't starve everything else. |

**Prioritize** — marks traffic for priority queuing, no bandwidth cap. Use for anything you want to go fast.
**Prioritize and Limit** — caps bandwidth AND marks as lowest priority. Use for Torrent — set the upload limit to something like `15 Mbps` (leaving ~5 Mbps headroom on a 20 Mbps uplink) so it physically cannot consume the full pipe.

**Torrent**: Set Upload Burst: "Short" in QoS policy
