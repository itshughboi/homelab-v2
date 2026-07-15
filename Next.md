- [x] Cut Athena's bind9 over from loose dock-prod-era files to the repo's compose.yaml
- [x] SOPS age key generated + backed up (Athena)
- [x] Gitea deployed on Athena, routed via Traefik static config (dock-prod)
- [x] Migrated GitHub repo (history + issues) into Gitea as `hughboi/homelab`; Gitea is now primary, GitHub is a push mirror
- [x] Grab Gitea Actions runner registration token, start the runner
- [x] Deploy Semaphore on Athena (hit + fixed a real Proxmox CPU-type bug along the way — Athena's VM never actually got the `host` CPU type Terraform declares)

Tomorrow:

- [x] Fixed VPN/Tailscale bypassing Traefik on Athena-hosted services — pointed gitea/semaphore.hughboi.cc's A records at dock-prod (10.10.10.10) instead of Athena directly, so every client (LAN/VPN/public/Athena-itself) routes through Traefik uniformly. IP:port (10.10.10.8:3000/:3001) still works as a fallback if Traefik is ever down. Hit and fixed two real bugs along the way: (1) hand-edited zone files with `update-policy` set are "dynamic" and silently ignore plain `rndc reload` — needs freeze/reload/thaw, see Terraform Bind9.md; (2) Athena's DNS resolver preference (bind9 first) was set via netplan, which cloud-init wipes on every reboot — moved to a systemd-resolved drop-in instead
	- [ ] Add the systemd-resolved DNS drop-in to the `setup-athena` Ansible playbook so a rebuilt Athena gets it automatically instead of needing this manual step again
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