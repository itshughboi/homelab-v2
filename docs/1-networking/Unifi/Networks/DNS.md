## Gateway Encrypted DNS (DoH)
Isolated networks (IoT, Guest, Torrent, Provisioning) use the UXG Max gateway as their DNS resolver. The gateway proxies all outbound DNS through Quad9 via DoH using CyberSecure Encrypted DNS — clients get encrypted DNS without needing Bind9 or AdGuard.

**Setup:** Settings → CyberSecure → Encrypted DNS → enable
- Cloudflare-security (1.1.1.1 & 1.0.0.2)
- Quad9-doh-ip4-port443-filter-ph

Leave DNS set to **Auto** on these networks in UniFi. The gateway intercepts outbound DNS and encrypts it automatically.

> [!NOTE]
> Internal networks (Management, k3s, Tailscale, WireGuard) use Bind9 → AdGuard → Unbound → Quad9, which already encrypts upstream queries. CyberSecure Encrypted DNS only needs to apply to isolated networks that bypass the internal resolver chain.

---

## DNS Per-Network

Networks using internal DNS: Settings → Networks → [Network] → Advanced → DHCP Name Server → uncheck Auto, specify servers.

Networks using gateway DNS (IoT, Guest, Torrent, Provisioning): leave DNS set to **Auto**.

Networks with DHCP disabled (k3s, Storage): DNS is not distributed by UniFi — set in Terraform cloud-init (k3s nodes) or statically on each machine (TrueNAS, PBS).

| Network       | DNS servers                                | Reason                                                                                        |
| ------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Management    | `10.10.10.8` (+ Bind9 secondary when live)  | **Bind9 only.** Dropped `10.10.10.10`/`9.9.9.9` — round-robin would intermittently bypass internal resolution + filtering. |
| k3s           | `10.10.10.8` (+ Bind9 secondary when live)  | **Bind9 only**, set via cloud-init (DHCP disabled). Resolves via the Athena primary so k3s can cold-boot. |
| Storage       | `9.9.9.9`, `1.1.1.2`                       | Package updates only. **DHCP disabled — configure statically on each machine (TrueNAS, PBS)** |
| Tailscale VPN | `10.10.10.8` (+ Bind9 secondary when live)  | Bind9 only — same as management. |
| WireGuard VPN | `10.10.10.8` (+ Bind9 secondary when live)  | Bind9 only — remote clients still get internal resolution + filtering via Bind9. |
| Torrent       | Auto (gateway DoH)                         | Airgapped — no internal IPs. Gateway proxies to Quad9 via DoH.                                |
| IoT           | Auto (gateway DoH)                         | Untrusted devices must not reach internal resolvers                                           |
| Guest         | Auto (gateway DoH)                         | Internet DNS only, encrypted via gateway                                                      |
| Provisioning  | Auto (gateway DoH)                         | Legacy netboot VLAN — unused (provisioning moved to Ventoy USB)                                |

### DNS Resolution Chain

- Bind9 (`10.10.10.8`) is authoritative for `*.hughboi.cc` and `*.hughboi.vip` — answers these directly from zone files
- All other queries are forwarded to AdGuard (`10.10.10.10`), which handles ad/tracker blocking
- AdGuard passes unblocked queries to Unbound, which does full recursion via Quad9
- If AdGuard is unreachable, Bind9 falls back to `9.9.9.9` (Quad9) directly

> [!WARNING] DHCP DNS is NOT primary/failover — it's queried in parallel
> Clients do **not** use the listed resolvers in strict order with failover. The OS queries
> them in parallel / round-robin and caches whichever answers first. Consequences of mixing
> different resolvers in one list:
> - Listing **`9.9.9.9`** alongside internal resolvers means clients **intermittently bypass
>   both local resolution (Bind9) and ad-filtering (AdGuard)** — `*.hughboi.cc` randomly fails
>   and ad-blocking silently leaks. `9.9.9.9` should only be Bind9's *own* upstream fallback,
>   never in the client-facing list.
> - Listing **AdGuard (`.10`) as a peer of Bind9** only works if AdGuard forwards
>   `*.hughboi.cc` to Bind9 — otherwise local names fail whenever a client happens to pick
>   `.10` first.
>
> **Rule of thumb:** every resolver handed to a given client must resolve the *same* things.
> Don't mix a full resolver with a partial one as "primary/secondary."

---

## Target DNS Design (planned — not yet implemented)

> The per-network table below still reflects the **current/live** config. This section is
> the agreed target. Two principles drive it: (1) every resolver handed to a given client
> must answer the *same* things (no mixing full + partial resolvers), and (2) DNS must
> survive any single host failure.

### Resolver per population

Assign DNS **per network** — one consistent resolver per client population, never a mixed list:

| Population | Resolver(s) | Why |
| --- | --- | --- |
| **Trusted** — Mgmt, k3s, VPN, Storage | Bind9 primary (`.8`) **+ Bind9 secondary** | Two *identical* Bind9 instances (zone-transfer). Safe to list both — parallel querying stays consistent. This is the HA. |
| **Filtered** — WiFi, IoT, TV, Guest | AdGuard only (k3s MetalLB VIP) | Ad/tracker blocking for the devices that want it. Conditional-forwards local zones to Bind9. |

Drop `9.9.9.9` from every **client-facing** list — it stays only as Bind9's own upstream.

### Placement — spread across failure domains

The current problem: Bind9 (Athena VM) and AdGuard (Docker VM) **both run on pve-srv-1**, so
one host dying kills all DNS. Target spreads them:

| Service | Runs on | Serves |
| --- | --- | --- |
| Bind9 **primary** | Athena VM (pve-srv-1) | Trusted nets (authoritative for `*.hughboi.cc` / `*.hughboi.vip`) |
| Bind9 **secondary** | k3s (pve-srv-2/3/4), MetalLB VIP | Trusted nets — AXFR/IXFR zone transfer from primary |
| **AdGuard** | k3s (pve-srv-2/3/4), MetalLB VIP | WiFi/IoT/TV/Guest only |

No single Proxmox host failure can take out trusted DNS (primary on srv-1, secondary on
srv-2/3/4). AdGuard and Bind9 serve different populations, so they were never redundant for
each other — **Bind9 HA = a second Bind9, not Bind9 + AdGuard.**

> [!IMPORTANT] ⚠️ AdGuard cutover — when k3s AdGuard goes live, repoint off dock-prod
> AdGuard currently runs on **dock-prod (`10.10.10.10`)**. When the k3s AdGuard
> (`10.10.30.65`, MetalLB VIP) is up, switch **everything** that points at `10.10.10.10` for DNS
> over to `10.10.30.65`, then retire the dock-prod AdGuard. Checklist:
> - [ ] UniFi DHCP DNS for the **filtered networks** (WiFi, IoT, TV, Guest) → `10.10.30.65`
> - [ ] Bind9's forward/fallback references to AdGuard (`10.10.10.10` → `10.10.30.65`)
> - [ ] Any docs/configs still naming `10.10.10.10` as the AdGuard resolver (`grep -r 10.10.10.10`)
> - [ ] Confirm the k3s AdGuard conditional-forwards local zones to Bind9 (`10.10.10.8`) before cutover
> - [ ] Decommission the dock-prod AdGuard container once clients are confirmed on `.65`

> [!NOTE] Secondary placement is still being decided
> The k3s-hosted secondary (above) is the leading option; the alternative is a **dedicated Bind9
> VM on a different Proxmox host** (simpler, no k3s dependency for the secondary). Either is valid
> for HA as long as it lives on a *different host than the primary* — decide before implementing.
> Near-term priority.

> [!NOTE] No circular dependency
> k3s nodes themselves resolve via Bind9 *primary* on Athena (.8), not via the k3s-hosted
> resolvers — so k3s can cold-boot without needing its own pods for DNS. The k3s-hosted
> Bind9 secondary and AdGuard are downstream of that.

### AdGuard: conditional-forward, do NOT rewrite

So AdGuard returns Bind9's authoritative answers (not a flattened single IP), set **Upstream
DNS servers** in AdGuard to conditionally forward the local zones:

```
[/hughboi.cc/]10.10.10.8
[/hughboi.vip/]10.10.10.8
```

Everything else uses AdGuard's filtered/recursive upstreams. **Don't** use a DNS rewrite of
`*.hughboi.cc → 10.10.10.10` — that would resolve *every* local name to the Traefik IP,
diverging from Bind9 (e.g. `athena.hughboi.cc` would wrongly point at .10).

### Bind9 secondary (zone transfer)

The secondary is a real Bind9 configured as a `secondary`/`slave` that pulls zones from the
primary via AXFR/IXFR — so it's an *identical* resolver, not a separate config to maintain:

- **Primary** (`also-notify` + `allow-transfer { <secondary-ip>; }`) pushes zone updates.
- **Secondary** (`type secondary; primaries { 10.10.10.8; };` per zone) auto-syncs.
- Both forward non-local queries the same way (→ AdGuard/Unbound → Quad9), so trusted clients
  get the same answer regardless of which they hit.

> Once AdGuard serves Guest/IoT directly, the UniFi Content Filter (below) becomes a redundant
> second layer for those networks rather than the primary ad-block — keep it or drop it, your
> call, but it's no longer load-bearing.

---

### UniFi Content Filter

Guest and IoT use gateway DNS, not internal resolvers — so Bind9/AdGuard ad blocking doesn't apply to them. Use UniFi's built-in content filter instead:

Settings → CyberSecure → Content Filter → Create filters for Guest and IoT → Adblock Enabled

---

## mDNS Proxy

Settings → Networks → [Network] → Advanced → mDNS

Bridges multicast DNS announcements between VLANs so Home Assistant (k3s VLAN 30 or Docker on VLAN 10) can discover smart home devices (IoT VLAN 50).

**Current config:**
- VLANs in proxy:
	- Management (10)
	- k3s (30)
	- IoT (50)
- Scope to specific device types (Chromecast, Apple TV, Sonos) — prevents all k3s services from being announced into IoT

> [!NOTE]
> If UniFi's mDNS forwarder proves unreliable (devices disappear after a few hours), deploy an Avahi container bridged across both VLANs. It's more reliable than the built-in forwarder for complex mDNS setups.
