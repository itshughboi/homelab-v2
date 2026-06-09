---
title: "NTP — Internal Time Source"
---

# NTP — Internal Time Source

> Status: **planned.** Today every host syncs time independently from public NTP over WAN.
> This documents moving to a single internal time source.

## Why this matters

Accurate, **consistent** time across the fleet isn't cosmetic:

- **Corosync** (Proxmox cluster) is timestamp-sensitive — skew between nodes can cause
  membership flaps and **fencing** (a node hard-reboots itself).
- **TLS everywhere** — k8s API, etcd, every HTTPS cert validates `notBefore/notAfter`. Skew
  breaks handshakes.
- **Wazuh correlation** — the SIEM is only useful if timestamps line up across hosts.
- TOTP, backups, log ordering all assume good time.

The failure mode to avoid: WAN blips (or a node can't reach the internet — exactly what
happens as k3s→WAN is tightened), nodes drift independently, and you get spurious fencing or
cert errors that are miserable to diagnose. The fix is **one source of truth** that all nodes
share — for Corosync, *consistency* matters more than absolute accuracy, and an internal
server keeps all nodes agreeing even if WAN is down.

---

## Approach — UXG Max as the NTP server

The gateway can serve time to the network; no extra host needed.

**1. Gateway upstream.** Settings → Internet → (WAN) — gateway syncs from public NTP/pool
(or `9.9.9.9` / `time.cloudflare.com`). This is the gateway's own clock source.

**2. Hand the gateway out as the NTP server to DHCP clients.** Per network:
Settings → Networks → [Network] → Advanced → **DHCP Option 42 (NTP Server)** → `10.10.10.254`
(the gateway). DHCP clients then sync from the gateway.

**3. Static hosts (Proxmox nodes, k3s, TrueNAS, PBS) don't use DHCP** — point them manually.
Proxmox/Debian use `chrony` (or `systemd-timesyncd`):

```sh
# /etc/chrony/chrony.conf — replace pool lines with:
server 10.10.10.254 iburst
# then
sudo systemctl restart chronyd
chronyc sources    # confirm it's tracking 10.10.10.254
```

For the Proxmox cluster specifically, **all nodes must point at the same source** — set this
on every node so Corosync sees consistent time.

> [!NOTE] Fallback if the gateway's NTP proves flaky
> Some UniFi gateways serve NTP unreliably. If `chronyc sources` shows the gateway
> unreachable/unstable, run `chrony` on **Athena (10.10.10.8)** as the internal server
> (peers upstream, serves the LAN) and point everything there instead. Same design, more
> robust daemon.

---

## Firewall

Clients reach the gateway's own NTP service, so the destination is the **Gateway** zone on
**UDP 123**:

```
<MGMT, k3s, Storage> → Gateway   UDP 123   ALLOW
```

The `CORE` port group already includes NTP 123, but those rules target **WAN** — internal NTP
is to the **Gateway**, so add the explicit Gateway:123 allow if time sync fails after the
switch. (If you use the Athena fallback instead, allow `<zones> → 10.10.10.8 UDP 123`.)

---

## Related

- Corosync's dependence on consistent time: [2-proxmox/pve/Corosync.md](../../../2-proxmox/pve/Corosync.md)
