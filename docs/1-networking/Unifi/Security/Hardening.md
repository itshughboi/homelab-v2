## Encrypted DNS on the Gateway

Settings → Internet → DNS

- Enable DoT/DoH for the gateway's own resolver — this only affects how the **UXG Max itself** resolves DNS (system updates, controller calls), not client traffic
- Client traffic already routes to Bind9 on Athena (10.10.10.8); this setting doesn't change that
- The higher-impact config is Bind9 forwarding upstream via Quad9 DoH — see [Networks/DNS.md](../Networks/DNS.md)

---

## TLS Certificate for the Local Controller

- Do **not** install UniFi's self-signed cert on clients — it breaks on controller reinstall
- Preferred approach: generate a local CA → issue a cert for the controller → install only the CA cert on your Mac
- If you primarily use [unifi.ui.com](https://unifi.ui.com) (cloud portal), this is low priority

---

## Spanning Tree

Settings → Switching → Spanning Tree

Use **RSTP** (Rapid Spanning Tree Protocol).

| Protocol | Reconvergence | Use case |
| --- | --- | --- |
| STP (802.1D) | 30–50 seconds | Legacy, avoid |
| **RSTP (802.1w)** | **1–2 seconds** | **Use this** |
| MSTP (802.1s) | 1–2 seconds | Multi-instance, overkill for this topology |

RSTP reconverges in 1–2 seconds vs 30–50 for classic STP — critical if a link flaps. MSTP adds per-VLAN spanning tree instances which aren't needed here. UniFi may auto-select RSTP but verify it's set explicitly.
