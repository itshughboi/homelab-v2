Good security measure will be to put firewall restrictions to my dns server to specific subnets. Super low risk in my environment, but good to be in practice of restricting internal dns servers to authorized subnets




## Unifi
- Management network needs DHCP option to point to netbootxyz machine to load iPXE
    - see for more info: iac\bootstrap\README.md   
- Each Proxmox node will need 3 virtual interfaces. `pve-srv-1` should have **2**+ physical NICs.
	1. Management / Cluster VLAN
	2. Storage VLAN - MTU 9000
- Apply QoS to **VLAN 20** with QoS to prioritize Corosync traffic.
- Allow Jumbo Frames on **VLAN 40** << 6x more data per packet. Maaximizes throughput + Minimizes overhead 

> [!DANGER] Jumbo Frames
> Every device on VLAN 40 (Proxmox, Truenas, PBS) MUST support and be configure for **MTU 9000** or else packets will drop. Jumbo packets can't go over the internet which is why we created this VLAN specifically for internal storage

| Virtual Interface | Target VLAN | Gateway      | MTU  |DHCP 67
| :---------------- | :---------- | ------------ | ---- |-----------
| **vmbr0.10**      | 10          | 10.10.10.254 | 1500 |10.10.99.99
| **vmbr0.20**      | 20          | None         | 1500 |
| **vmbr0.40**      | 40          | None         | 9000 |
<br>

- Create the following networks in Unifi << CAN BE DONE WITH ANSIBLE

| Name         | VLAN ID | CIDR           | Notes                  |
| ------------ | ------- | -------------- | ---------------------- |
| Management   | 1       | 10.10.10.0/24  | SSH, Web UI, Unifi, Bind9
| Cluster      | 2       | 10.10.20.0/24  | Corosync               | 
| k3s          | 3       | 10.10.30.0/24  |                        |   
| Storage      | 4       | 10.10.40.0/24  | TrueNAS, PBS, Longhorn |
| VPN          | 8       | 10.10.80.0/24  | Tailscale              |
| Torrent      | 49      | 172.16.49.0/24 |                        |
| Provisioning | 99      | 10.10.99.0/24  | Netboot                |


### Additional Notes:

**VLAN 20**: Corosync is very sensitive to latency. If I'm flooding a NIC with backups or storage retrieval, it can cause jitter and fuck with Proxmox and may cause a Fencing (Hard Reboot) event. Problem is that I enjoy seeing the webUI at 10.10.10.x/24. This has **NO GATEWAY**. Only internal routing.<br>

**VLAN 40**:  Similar to VLAN 20, PBS or Longhorn can saturate the management NIC which can slow down SSH or Athena VM. This has **NO GATEWAY**. Only internal routing. **Jumbo Frames** enabled



## Purpose
Self-hosted UniFi controller configuration for:
- VLAN segmentation
- Homelab infrastructure
- Monitoring via Prometheus/Grafana
- Integration with Homepage dashboard

<br>


### Notes
Users
- Local Admin (hughboi)
  - Used for direct controller login
  - No cloud dependency

- Ubiquiti Cloud Account (Hughboi - Gmail / Fastmail)
  - Used for remote access via unifi.ui.com


<br>

### Device Adoption
```sh
set-inform http://unifi.hughboi.cc:8080/inform
```
or
```sh
set-inform http://10.10.10.10:8080/inform
```
> If adoption fails or resets, run `set-inform` twice (usually caused by a previous device adoption)

<br>

### VLANs
| Name         | VLAN | Subnet         |
| ------------ | ---- | -------------- |
| Management   | 1    | 10.10.10.0/24  |
| k3s          | 3    | 10.10.30.0/24  |
| VPN          | 8    | 10.10.80.0/24  |
| torrent      | 49   | 172.16.20.0/24 |
| Provisioning | 99   | 10.10.99.0/24  |

<br>

### UXG
| Port | Device        |
| ---- | ------------- |
| 1    | Synology      |
| 2    | Netboot       |
| 3    | -             |
| 4    | USW Flex Mini |
| 5    | WAN           |

<br>

### Flex Mini
| Port | Device    |
| ---- | --------- |
| 1    | pve-srv-1 |
| 2    | pve-srv-2 |
| 3    | pve-srv-3 |
| 4    | pve-srv-4 |
| 5    | UXG       |

<br>

### Settings
- Networks -> Rogue DHCP Server Detection (Checked)
- Enable 2FA for admin users

<br>

### Backups
1. Auto backups (.unf) stored locally under data/unifi/backups
2. PBS image backup -> Synology
3. Restic container / file backup - > TrueNAS
4. Rsync data/unifi/backups to data/filebrowser << Just for simplicity sake of restoring. Not really 'backups'


<br>


### Homepage Integration
Documentation: https://gethomepage.dev/widgets/services/unifi-controller/
1. Create a local user with permissions of **View Only** (Might need to switch to old UI) <br>

*Widget:*
```sh
   - Unifi:
        href: https://10.10.10.10:8443                # https://unifi.hughboi.cc
        siteMonitor: https://10.10.10.10:8443         # https://unifi.hughboi.cc
        icon: unifi.png
        widget:
            type: unifi 
            url: https://10.10.10.10:8443             # https://unifi.hughboi.cc
            username: {{HOMEPAGE_VAR_UNIFI_USERNAME}}
            password: {{HOMEPAGE_VAR_UNIFI_PASSWORD}}
            fields: ["uptime", "wlan_users"]
```
\
<br>
<br>

# Unifi Poller (Grafana)
> [!Warning] Use Prometheus as InfluxDB 2.x is NOT supported
> 
> 

### Flow
UniFi Controller API
  - unifi-poller (scrapes controller)
  - Prometheus (scrapes poller)
  - Grafana (visualizes Prometheus)

## Unifi Authentication
1. Create a new user on Unifi that poller can login to (unifi-poller)
	1. Permissions: Read Only (all networks)

### Prometheus Connection
- We expose TCP port 9130 in the container to publish metrics at. We then create a prometheus job to scrape this endpoint:
```
 - job_name: 'unifipoller'
    scrape_interval: 30s
    static_configs:
    - targets: ['10.10.10.10:9130']
```

- Redeploy Prometheus and you should be able to see this as a target now and just make sure it checks and can query.
- I can also check that endpoint myself with this to query the poller metrics
```
curl http://10.10.10.10:9130/metrics
```
### Grafana Connection
- Data Source - > Add new data source -> Prometheus
	1. Name: Whatever
	2. Prometheus server URL: http://prometheus:9090 (internal DNS) on promgraftail
		1. Prometheus scrapes metrics of unifi-poller in prometheus.yml
	3. Authentication: None
	4. HTTP Headers: None
- Grafana dashboards link: https://grafana.com/grafana/dashboards/?search=unifi-poller

### Grafana Requirements
Plugins Required:
1. Clock
2. PieChart

```
grafana-cli plugins install grafana-clock-panel
grafana-cli plugins install grafana-piechart-panel
```

### Troubleshooting
Problem: No display in grafana even though everything is connected.
Fix: namespace it is querying is mismatched with what I am using. Add this label to the environment labels
```
- UP_PROMETHEUS_NAMESPACE=unpoller
```
Restart Prometheus and I should start seeing the graphs with visual data

<br>


### Dashboards
https://grafana.com/grafana/dashboards/?search=unifi-poller&dataSource=nobl9agent%2Cprometheus%2Cvictorialogs-datasource




## Break-Glass: Recovering from a Firewall Lockout

> [!CAUTION]
> This is the procedure used when firewall rules locked out the entire network —
> WAN dropped, Proxmox nodes unreachable on 22/8006, cloud portal unavailable,
> and Tailscale down. Root cause: new firewall rules blocked traffic to the
> UniFi controller VM (Athena/dock-prod, 10.10.10.10), which cascaded into the
> UXG Max losing controller contact and dropping WAN.

### Diagnosis Sequence

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

### Recovery Path (no cloud portal, no working SSH password for UXG Max)

> [!IMPORTANT] Why this path works
> The UniFi cloud portal needs WAN (down). SSH to the UXG Max needs the device
> password (not recorded). But traffic from a Proxmox HOST to its own VMs goes
> through the local Linux bridge (vmbr0) and NEVER touches the UniFi firewall.
> That's the way in.

1. **Physical console** (keyboard + monitor) on pve-srv-1.

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

### Alternative: Disable rules directly in MongoDB (if no clean backup)

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

### Lessons / Prevention

- [ ] **ALWAYS make firewall changes from unifi.ui.com**, never the local
      controller — the cloud portal survives a self-inflicted lockout (this is
      only true while WAN is up; if a rule kills WAN, even this fails).
- [ ] **Never block traffic to the controller VM (10.10.10.10)** — if the UXG
      Max can't reach its controller, it can cascade into WAN loss.
- [ ] **Record the UXG Max SSH device password** in Vaultwarden — would have
      been a faster recovery path than the console → VM → docker chain.
- [ ] **Take a manual backup before every firewall change** (this is what saved
      us — `autobackup` had a clean pre-change snapshot).
- [ ] Add an explicit `ALLOW MGMT → MGMT` rule above `ANY → MGMT DENY` so admin
      traffic within the management VLAN is never caught by the deny.
- [ ] Keep `established/related` as rule #1 in LAN IN.