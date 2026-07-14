- [x] Cut Athena's bind9 over from loose dock-prod-era files to the repo's compose.yaml
- [x] SOPS age key generated + backed up (Athena)
- [x] Gitea deployed on Athena, routed via Traefik static config (dock-prod)
- [x] Migrated GitHub repo (history + issues) into Gitea as `hughboi/homelab`; Gitea is now primary, GitHub is a push mirror
- [ ] Grab Gitea Actions runner registration token, start the runner
- [ ] Deploy Semaphore on Athena
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