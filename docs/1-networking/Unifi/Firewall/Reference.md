Zone names, trust levels, and port groups to use when writing rules.


## Zone Map
### System Zones (locked — UniFi-managed, cannot be removed)

| Zone         | Meaning                                                                                                                       | Networks assigned      |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| **External** | WAN — internet-facing interfaces. This is what rules call "WAN."                                                              | Internet 1, Internet 2 |
| **Gateway**  | The UXG Max device itself. Use for rules targeting the gateway (e.g. allow DNS to the UXG)                                    | —                      |
| **VPN**      | UniFi-native VPN clients (system-managed). Not used by this setup — both Tailscale and WireGuard have their own custom zones. | —                      |
| **Hotspot**  | Captive portal / guest portal networks                                                                                        | —                      |
| **DMZ**      | Exposed-host zone — servers reachable from External with limited internal access                                              | —                      |

> [!NOTE]
> Rules in this doc that reference "WAN" map to the **External** zone in the UniFi UI.
> Do not create a separate "WAN" zone — External already serves that purpose.

### Custom Zones

| Zone             |
| ---------------- |
| **MGMT**         |
| **Cluster**      |
| **IoT**          |
| **Torrent**      |
| **Tailscale**    |
| **Wireguard**    |
| **Guest**        |
| **k3s**          |
| **Storage**      |
| ~~**Provisioning**~~ — sunsetted (netboot abandoned), zone can be deleted |

---

## Architecture

| Layer | VLAN | Trust Level | UniFi Zone |
| --- | --- | --- | --- |
| Control Plane | Management (10) | Fully trusted | MGMT |
| Compute Plane | k3s (30) | Semi-trusted | — (verify) |
| Data Plane | Storage (40) | Highly restricted | — (verify) |
| Devices | IoT (50) | Untrusted | IoT |
| Edge / Risk Zone | Torrent (49) | Untrusted | Torrent |
| Access Plane | Tailscale VPN (80) | Conditionally trusted | Tailscale |
| Access Plane | WireGuard VPN (81) | Conditionally trusted | Wireguard |
| ~~Lifecycle~~ | ~~Provisioning (99)~~ | ~~Zero-trust / Disposable~~ | Sunsetted — netboot abandoned, [Ventoy](../../../2-proxmox/provisioning/Ventoy.md) now |

---

## Port Groups (UniFi Network Lists)

Defined in UniFi → Firewall & Security → **Network Lists** (type: Port), referenced by name in
firewall rules. **This is the single source of truth** — the **Used by** column maps every
[Rules.md](Rules.md) rule to its group, so when you build a rule in UniFi you pick exactly one
named group. (The old conceptual legend — SSH/CORE/WEB/etc. — is retired; it never matched the
actual UniFi objects and just created drift.)

> [!IMPORTANT] One port group per rule — design for it
> A UniFi firewall rule references **exactly one** port group, and you can't change that reference
> after the rule is created (you'd delete + recreate the rule). So each group below is a
> **complete, pre-merged superset** for its purpose: a rule that conceptually needs "SSH + web UIs"
> uses the single `admin` group, **not** two groups. The lists themselves *are* editable later
> (add a port → every rule using it picks it up), but the rule→list assignment is fixed. Lean
> slightly over-inclusive on trusted zones; never split a rule's needs across two groups.
>
> `ANY` / `DENY` rules use **no** port group (All ports).

| Network List   | Ports                            | Rule protocol | Used by (source → dest) |
| -------------- | -------------------------------- | ------------- | ----------------------- |
| `ssh`          | 22                               | TCP  | MGMT→Torrent, MGMT→VPN |
| `admin`        | 22, 80, 443, 8006, 8007          | TCP  | MGMT→Storage, MGMT→IoT, VPN→MGMT, VPN→Storage, WG→MGMT, WG→Storage |
| `dns`          | 53, 853                          | Both | k3s→Bind9 (`10.10.10.8`) |
| `wan-egress`   | 53, 80, 123, 443                 | Both | MGMT→WAN, k3s→WAN, IoT→WAN, Guest→WAN, WG→WAN |
| `torrent-wan`  | 53, 80, 123, 443, 6881–6889      | Both | Torrent→WAN |
| `k3s-api`      | 22, 6443, 8472, 10250            | Both | MGMT→k3s, VPN→k3s, WG→k3s |
| `storage-data` | 111, 2049, 3260, 9100, 9500–9504 | Both | k3s→Storage (NFS, iSCSI, node_exporter, Longhorn) |
| `nfs`          | 111, 2049                        | Both | Torrent→TrueNAS |
| `gitea`        | 3000                             | TCP  | k3s→Athena Gitea (ArgoCD pull) |
| `wg-in`        | 51820                            | UDP  | External→Gateway (WireGuard inbound tunnel) |
| `vpn-out`      | 41641, 3478, 443                 | Both | Tailscale→WAN (subnet-router egress) |

> [!NOTE] "Rule protocol" is set on the **rule**, not the list — Network Lists hold port numbers
> only. For mixed groups (e.g. `wan-egress` = DNS/NTP over UDP + HTTP/S over TCP) set the rule's
> protocol to **Both**. `wg-in` is UDP-only; `ssh`/`gitea` are TCP-only.
>
> `vpn-out` is a best-effort egress set for the Tailscale subnet router (direct `41641` + STUN
> `3478` + DERP `443`). If Tailscale struggles to connect, broaden it to all outbound — TS is
> finicky about egress ports.

### Migrating your current lists
You have four lists today; here's the delta to the set above:

| Current list | Ports today | Action |
| --- | --- | --- |
| `admin` | 22, 80, 443 | **Expand** → add `8006` (Proxmox) + `8007` (PBS) |
| `dns` | 53, 853 | **Keep** ✅ |
| `k3s-admin` | 111, 2049, 3260, 9100, 9500, 80, 443 | **Replace** → these are storage data-path ports; recreate as `storage-data` (drop `80`/`443`, add `9501–9504`). The k3s *API* gets its own `k3s-api` list. |
| `storage` | 111, **2048**, 22, 80, 443 | **Delete** → `2048` is a typo (NFS is `2049`); this conflated data-path + web. k3s→storage uses `storage-data`; admin web access uses `admin`. |

Then **create** the remaining new lists: `ssh`, `wan-egress`, `torrent-wan`, `k3s-api`,
`storage-data`, `nfs`, `gitea`, `wg-in`, `vpn-out`.
