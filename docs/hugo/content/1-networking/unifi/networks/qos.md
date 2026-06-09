---
title: "QoS"
---

## IGMP Snooping
**Enable per-VLAN.** Prevents multicast traffic from flooding every switch port — only forwards to ports that have requested membership.

Without it: Chromecast, Apple TV, Sonos, and other multicast-heavy devices send traffic to every port on the VLAN.

Enable on:
- Management (10)
- k3s (30)
- IoT (50)

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
