---
title: "List collections to find the right one"
---


> [!CAUTION]
> This is the procedure used when firewall rules locked out the entire network —
> WAN dropped, Proxmox nodes unreachable on 22/8006, cloud portal unavailable,
> and Tailscale down.
>
> **Confirmed symptom:** Mac on 10.10.10.x could not reach .1–.10, but *could* reach
> 10.10.10.15 (Synology). This rules out a blanket MGMT→MGMT deny — the issue was
> targeted at the infrastructure IP range.
>
> **Cause**: Enabled Block inter-VLAN traffic without a MGMT -> MGMT Allow rule in place first

## Diagnosis Sequence

1. **Confirm nodes are alive, not dead** — `filtered` ports mean a firewall is
   dropping packets, not that hosts are down:
```sh
nmap -Pn -p 22,8006 10.10.10.1 10.10.10.2 10.10.10.3 10.10.10.4
```
   `Host is up` + `filtered` = nodes alive, firewall blocking. (-Pn skips ping
   discovery, which is itself blocked.)

2. **Check ARP to confirm L2 reachability**:
```sh
arp -a | grep "10.10.10"
```
   Note: same-subnet traffic is switched at L2 and normally bypasses the UniFi
   router firewall — BUT UniFi's zone-based firewall CAN intercept intra-VLAN
   traffic depending on zone definitions. This is what bit us.

3. **Identify what's actually down**: WAN down at the same time as firewall
   changes = not coincidental. Controller VM (10.10.10.10) showing ARP
   `incomplete` = controller unreachable = UXG Max lost its brain.

## Recovery Path (no cloud portal, no working SSH password for UXG Max)

> [!IMPORTANT] Why this path works
> The UniFi cloud portal needs WAN (down). SSH to the UXG Max needs the device
> password (not recorded). But traffic from a Proxmox HOST to its own VMs goes
> through the local Linux bridge (vmbr0) and NEVER touches the UniFi firewall.
> That's the way in.

1. **Physical console** (keyboard + monitor) on pve-srv-1
   - Login with PAM user `root` as it doesn't use PVE for login

2. **SSH from the Proxmox host to the controller VM** — bypasses UniFi firewall
   entirely since it's local bridge traffic:
```sh
ssh hughboi@10.10.10.10
```

3. **Locate the controller + mongo containers**:
```sh
docker ps
```
   Stack: `unifi_controller` (jacobalberty/unifi) + `unifi_mongo` (mongo:3.6).
   MongoDB is a SEPARATE container, default port 27017 (NOT 27117).

4. **Restore from backup via the API** (one-liner — fastest fix). Backups live at
   `/home/hughboi/data/unifi/backup/autobackup/`:
```sh
curl -sk -c /tmp/c -XPOST https://localhost:8443/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"USER","password":"PASS"}' \
&& curl -sk -b /tmp/c -XPOST https://localhost:8443/api/s/default/cmd/restore \
  -F "file=@/home/hughboi/data/unifi/backup/autobackup/BACKUP_FILENAME.unf"
```
   `rc: ok` = accepted. The controller auto-restarts and applies the backup.

5. **Watch the controller come back up**:
```sh
docker logs -f unifi_controller
```
   Wait for log flood to settle (~60–90s). UXG Max auto-reconnects and pulls the
   pre-firewall config. WAN returns on its own.

## Alternative: Disable Rules Directly in MongoDB (if no clean backup)

> [!NOTE] Zone-based firewall stores rules in a DIFFERENT collection
> The legacy `firewallrule` collection was EMPTY in our case (returned
> matchedCount: 0). Zone-based rules live in `trafficrule` / `trafficrulegroup`.
> Always check collection names first.

```sh
# List collections to find the right one
sudo docker exec -it unifi_mongo mongo unifi --eval "db.getCollectionNames()"

# Disable zone-based rules (use single quotes so $set isn't shell-expanded)
sudo docker exec -it unifi_mongo mongo unifi \
  --eval 'db.trafficrule.updateMany({}, {"$set": {"enabled": false}})'

# Push config to gateway
docker restart unifi_controller
```

## Lessons / Prevention

- [x] **ALWAYS make firewall changes from unifi.ui.com**, never the local
      controller — the cloud portal survives a self-inflicted lockout (this is
      only true while WAN is up; if a rule kills WAN, even this fails).
- [x] **Never block traffic to the controller VM (10.10.10.10)** — if the UXG
      Max can't reach its controller, it can cascade into WAN loss. Covered by
      the `MGMT → MGMT ANY` rule now documented in the Management section.
- [ ] **Record the UXG Max SSH device password** in Vaultwarden — would have been a faster recovery path than the console → VM → docker chain.
- [x] **Take a manual backup before every firewall change** — `autobackup` is
      what saved us. Also consider a manual snapshot immediately before any change.
- [x] **`ALLOW MGMT → MGMT` is now rule priority 1** in the Management section —
      this was the missing rule that caused the June 2026 lockout. Zone-based
      firewall intercepts intra-VLAN traffic; without this, your own Mac on
      10.10.10.x cannot reach any other MGMT host.
- [x] **`established/related` is rule #1 in LAN IN** — documented in [README.md](README.md#setup).
      Verify this in UniFi after any restore.
