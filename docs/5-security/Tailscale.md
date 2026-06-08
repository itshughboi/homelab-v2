# Tailscale

---

## The Decision: Subnet Router (Not Exit Node)

For this homelab architecture, **Subnet Router** is the right choice. Exit Node adds
complexity without meaningful benefit for an admin workflow.

---

## Subnet Router (Current Setup)

Acts as a bridge — only handles traffic destined for the home network (`10.10.x.x`
and the Tailscale `100.x.x.x` range).

- **Performance:** Fast. Your laptop uses local internet for everything else;
  only Proxmox/k3s traffic goes through the tunnel.
- **Reliability:** If home internet goes down or the Tailscale VM hangs,
  your laptop still has internet access.
- **Use case:** Standard admin setup — manage gear without slowing down browsing.

**Start command:**
```sh
tailscale up --advertise-routes=10.10.10.0/24,10.10.30.0/24 --accept-routes
```

**Why `--accept-routes`:**
- `--advertise-routes` tells Tailscale "I can get you to the home VLANs"
- `--accept-routes` tells this VM "if another node advertises a route, I want to know about it" — needed for bi-directional transparency

---

## Exit Node (Why We're Not Using It)

Exit Node forces **all** laptop internet traffic through your home gateway.

- **Benefit:** Security on sketchy public Wi-Fi — all traffic encrypted until it hits your UniFi gateway
- **Problem:** Download speed capped by your home upload speed
- **Problem:** Can cause MTU/routing issues through subnet router → UniFi gateway double-NAT

Not worth it for solo admin use.

---

## UniFi Static Route (Required)

For subnet routing to work, add a static route in UniFi so internal VLANs can reach
remote Tailscale peers:

**Settings → Routing → Create New Route:**
- Destination: `100.64.0.0/10`
- Type: Next Hop
- Next Hop: Tailscale VM IP (`10.10.80.x`)

Without this, the tunnel works but inter-VLAN → Tailscale peer routing fails.

---

## Scope Note

VPN users can currently reach the entire `10.10.10.0/24` management subnet.
Fine as a solo user. If VPN access is ever shared, scope the destination to
specific IPs (Athena, Docker host) rather than the whole subnet.
