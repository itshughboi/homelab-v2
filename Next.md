- [x] Cut Athena's bind9 over from loose dock-prod-era files to the repo's compose.yaml
- [x] SOPS age key generated + backed up (Athena)
- [x] Gitea deployed on Athena, routed via Traefik static config (dock-prod)
- [x] Migrated GitHub repo (history + issues) into Gitea as `hughboi/homelab`; Gitea is now primary, GitHub is a push mirror
- [x] Grab Gitea Actions runner registration token, start the runner
- [x] Deploy Semaphore on Athena (hit + fixed a real Proxmox CPU-type bug along the way — Athena's VM never actually got the `host` CPU type Terraform declares)

Tomorrow:

- [ ] Decide + implement real fix for VPN/Tailscale bypassing Traefik on Athena-hosted services (gitea.hughboi.cc, semaphore.hughboi.cc resolve straight to 10.10.10.8:443 over Tailscale, nothing listens there)
	- [ ] Keep IP:port as the fallback regardless — even if gitea.hughboi.cc works reliably, direct :3000/:3001 access should stay usable if dock-prod's Traefik itself is ever down (already true today, worth preserving)
	- [ ] Weigh: Traefik on Athena, made authoritative only for VPN/LAN clients (via split-horizon DNS) so dock-prod's Traefik stays the WAN path and Athena doesn't become a second copy of the same public-facing config to maintain
	- [ ] Alternative: split-horizon DNS alone, routing Tailscale clients to dock-prod's IP instead of Athena's, so VPN traffic just takes the same path as everyone else (no new Traefik instance, but internal traffic loops out through dock-prod oddly)
- [x] SOPS-encrypt Semaphore's `.env` (`./scripts/sops-migrate.sh semaphore`) — first real service through the SOPS workflow (also fixed a real bug in the script itself: missing `--filename-override` meant it never matched any creation rule for any service, ever)
- [ ] Actually configure Semaphore: SSH key, point at Gitea repo, inventory, task templates
- [ ] Watch one more Gitea Actions CI run go green to confirm the runner is solid, not a one-off
- [ ] Update `terraform/bind9/credentials.tfvars` with the new TSIG key (regenerated tonight, old one deferred)
- [ ] Fix dock-prod's own DNS resolver pointing at dead `10.10.10.9` (already tracked in docs/6-docker/index.md TODO)
- [ ] Spot-check other hosts for Terraform-declared vs. live-VM drift (Athena had wrong core count + name before tonight — worth confirming it was a one-off)
- [ ] Flash ventoy images and boot up each pc
- [ ] Move management VLAN to 10 (test)
- [ ] Get mini pcs inventory in Unifi/Assignments/Inventory
	- [ ] Update MAC Reservations after that
	- [ ] Verify which is 2.5 GbE and which is 1 GbE
- [ ] Configure/update with ansible playbook
- [ ] Do Adguard cutover when i have k3s adguard up [[docs/hugo/content/1-networking/unifi/networks/dns|dns]]
	- [ ] Couple things in here I need to configure, veryify, and change. Couple contradictions in what networks get what dns sesrvers
- [ ] Decide on if Proxmox should have VLAN 40 for PBS 
- [ ] Once monitoring is up and going, revisit [[docs/hugo/content/1-networking/unifi/security/logging|logging]] with Unifi
	- [ ] implement unifi honeypot


Things to do when i get more hardware:
- lacp
- dedicated storage NICs for all servers separate from management/corosync
- channel AI when I get unifi AP up and going