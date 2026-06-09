---
title: "Reference"
---

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

## Service Groups (Legend)

Conceptual groups used in the rule tables in [Rules.md](Rules.md). See **UniFi Network Lists** below for the actual port groups configured in UniFi.

| Group | Ports |
| --- | --- |
| SSH | 22 TCP |
| CORE | DNS 53 TCP/UDP, DHCP 67/68 UDP, NTP 123 UDP |
| WEB | HTTP 80 TCP, HTTPS 443 TCP, Proxmox 8006 TCP, PBS 8007 TCP |
| ~~BOOT~~ | ~~TFTP 69 UDP, HTTP/HTTPS (PXE)~~ — sunsetted (was for netboot; no longer used) |
| STORAGE | NFS 2049, rpcbind 111, SMB 445, iSCSI 3260 |
| COROSYNC | 5404–5405 UDP, 2224 TCP |
| K3S | 6443 TCP, 8472 UDP |
| MONITOR | 9100, 9090, 3000, 3100, 8086 TCP |
| TORRENT | 6881–6889 TCP/UDP |
| VPN | 41641 UDP (Tailscale), 51820 UDP (WireGuard) |

---

## UniFi Network Lists (Port Groups)

Defined in UniFi → Firewall & Security → Network Lists. Referenced by name in firewall rules.

| List name   | Ports                       | Notes                                        |
| ----------- | --------------------------- | -------------------------------------------- |
| `admin`     | 22, 80, 443, 8006, 8007     | SSH + web UIs including Proxmox and PBS      |
| `k3s-admin` | 111, 2049, 3260, 9100, 9500 | rpcbind, NFS, iSCSI, node_exporter, Longhorn |
| `storage`   | 111, 2049, 22, 80, 443      | Admin access to storage nodes                |
| `dns`       | 53, 853                     | DNS + DoT                                    |
