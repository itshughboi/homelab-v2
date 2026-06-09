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
| Management    | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | athena, adguard, bind9                                                                        |
| k3s           | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | **DHCP disabled — set via cloud-init in Terraform, not from UniFi**                           |
| Storage       | `9.9.9.9`, `1.1.1.2`                       | Package updates only. **DHCP disabled — configure statically on each machine (TrueNAS, PBS)** |
| Tailscale VPN | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Same as management                                                                            |
| WireGuard VPN | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Remote clients need internal resolution                                                       |
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

> [!TIP] Target design (recommended)
> Assign DNS **per network**, one consistent resolver per client population — not a mixed list:
>
> | Population | Resolver(s) | Notes |
> | --- | --- | --- |
> | Trusted (Mgmt, k3s, VPN, Storage) | Bind9 primary (`.8`) **+ Bind9 secondary** | Two *identical* Bind9 instances (zone-transfer/AXFR). Safe to list both — parallel querying is consistent. Fixes the single-point-of-failure. |
> | WiFi / IoT / TV + Guest | AdGuard only (k3s MetalLB VIP) | AdGuard forwards `*.hughboi.cc` → Bind9 so these devices still resolve local names; everything else it filters + recurses. |
>
> Drop `9.9.9.9` from all client-facing lists (keep it only as Bind9's upstream). AdGuard is
> the dedicated resolver for the WiFi/guest population — **not** a "secondary" to Bind9.
> Bind9 HA = a second Bind9, not Bind9 + a different resolver.
> *(Not yet implemented — current per-network table below still reflects the live config.)*

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
