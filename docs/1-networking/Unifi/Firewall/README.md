Zone-based firewall rules for the UXG Max. This setup uses **zone-based firewall only** — see the warning below before touching anything.

| File | Contents |
| --- | --- |
| [Reference.md](Reference.md) | Zone map, architecture, service groups, port groups |
| [Rules.md](Rules.md) | Per-VLAN rule tables and global rule order |
| [Recovery.md](Recovery.md) | Break-glass lockout recovery procedure |

---

> [!IMPORTANT]
> **Three rule systems exist in UniFi. Do not mix them.**
>
> | System | What it is | Use? |
> | --- | --- | --- |
> | **Object Oriented Networking (OON)** | Assigns Secure/Route/QoS/Schedule to devices/networks → auto-generates zone rules | Only if you commit fully to it |
> | **Zone-based firewall** | Manual zone-pair policies. What this folder describes. | **Yes — this setup uses this** |
> | **Legacy (LAN IN / LAN OUT / LAN LOCAL)** | Old per-direction rule system, being deprecated | No — never add rules here |
>
> OON sits above zones and writes auto-generated rules into the same zone rule table as your manual rules. If you have both OON objects AND manual zone rules for the same traffic, they can conflict or one can silently override the other depending on rule order.
>
> **If you have OON objects (e.g. `MGMT -> Allow ALL`, `VPN -> Allow ALL`):** check the Routing Table to see what rules they generated. If they're creating broad allow-all rules, they may be undermining specific port-level DENYs in your zone config. OON is too coarse for a multi-VLAN setup with per-port restrictions — it cannot express "MGMT → Storage only on 22, 80, 443, 8006, 8007."
>
> Confirmed zone-based: the lockout incident showed rules in MongoDB `trafficrule` collection (zone), not `firewallrule` (legacy).
> Network Lists (port/IP groups) are named objects used *within* zone rules — not a separate system.

> [!WARNING]
> **Always make firewall changes from [unifi.ui.com](https://unifi.ui.com), not the local controller at `10.10.10.10:8443`.**
> The controller is self-hosted, but the linked cloud account at unifi.ui.com reaches it independently of your local network.
> If a rule blocks your own VLAN, the local controller becomes unreachable — the cloud portal is the way back in.
> This only works while WAN is up. If a rule kills WAN too, see [Recovery.md](Recovery.md).

---

## Rule Behavior

> [!TIP]
> **Rules are one direction only — always model the initiator.**
> Only create a rule for the side that *starts* the connection. The `established/related` rule handles response traffic automatically.
> Example: `MGMT → Torrent TCP 22` lets you SSH from MGMT into Torrent. You do not need a second rule for Torrent → MGMT. If you find yourself creating mirrored pairs, stop — the return rule is doing that work.

> [!IMPORTANT]
> **Always put the service port in Dst. Port — never Src. Port.**
> When a client initiates a connection, it connects *from* a random ephemeral port (e.g. 54832) *to* the service's well-known port (22, 80, 443) on the destination.
> A rule with `Src. Port = 22` will never match normal SSH traffic — the source port is unpredictable.
> Leave Src. Port blank (Any). Only fill in Dst. Port.
>
> **You can comma-separate multiple ports in a single rule** instead of creating one rule per port.
> Example: one rule with Dst. Port `22,80,443` replaces three separate SSH/HTTP/HTTPS rules.
> UniFi has no named port groups in the zone-based firewall UI — consolidate inline instead.

---

## Setup

> [!DANGER]
> **Add ALL rules before enabling any blocking.** With Allow All as the default you can
> work freely without locking yourself out. Flip the blocking switches only after every
> rule is in place. Do steps 3 and 4 from `unifi.ui.com` (cloud/out-of-band) so you
> have a fallback if you lock yourself out of the local controller.

1. **Add all rules from [Rules.md](Rules.md)** while the default is still Allow All — including the intra-VLAN rules below.

2. **Add the established/related rule as the very first rule in LAN IN:**
   `ALLOW ALL → ALL  state: established, related`
   Permits return traffic for all initiated connections. Without it, outbound ALLOWs work but responses get dropped.

3. **Enable "Block inter-VLAN traffic"** on each network: Settings → Networks → [Network] → Advanced.
   Only affects cross-VLAN routing — same-subnet traffic is unaffected. Safe to enable once your allow rules are in place.

4. **Set Security Posture to Block** in Settings → Networks → Default Security Posture.
   Makes `Block All Traffic` the effective default deny. Without it, an `Allow All Traffic` system rule overrides your explicit denies and leaves inter-VLAN paths open regardless.
   After enabling, verify WAN access for each zone that needs it: `MGMT → WAN`, `K3S → WAN`, `TORRENT → WAN`, `PROVISIONING → WAN`.

   > [!NOTE] **The rule list will still show many "Allow All Traffic" system rules after switching to Block — this is normal.**
   > Those rules apply to UniFi's built-in zones (Internal, Gateway, VPN, Hotspot, DMZ), not your custom zones.
   > Gateway → all zones is required for the UXG Max itself to handle DHCP, DNS, and routing.
   > Traffic between your custom zones (MGMT, k3s, Storage, IoT, Torrent, etc.) is governed solely
   > by your explicit allow rules and the Block All default. Verify with a quick test: ping from an
   > IoT device to `10.10.10.10` — it should time out.

### Intra-VLAN Rules

UniFi's zone-based firewall can intercept same-subnet traffic. Without these, devices on the
same VLAN cannot reach each other once Block is enabled.

| Rule | Why |
| --- | --- |
| `MGMT → MGMT ANY` ALLOW | Mac → pve-srv, Mac → UniFi controller. Missing this = June 2026 lockout. |
| `k3s → k3s ANY` ALLOW | Pod networking and API server node-to-node traffic |
| `Storage → Storage ANY` ALLOW | PBS → TrueNAS backups |

Cluster (VLAN 20) is exempt — no gateway, purely switched, never reaches the zone firewall.
IoT, Guest, Torrent, and Provisioning do not need intra-VLAN rules.

> See [Security.md](../Security.md) for IPS, region blocking, honeypot, NetFlow, and logging settings.
> See [Networks.md](../Networks.md) for DNS and per-VLAN configuration.
