# Network Tests

Ansible playbooks for network performance testing, troubleshooting, and auditing. Each playbook is self-contained with its own `inventory.yaml` — edit the inventory to match your environment before running.

All playbooks follow the same pattern:
1. Run tests on remote hosts
2. Write results to `/tmp/<playbook-name>/` on each host
3. Fetch results back to the controller node

---

## Playbooks

### `dns-latency/`
**Tools:** `dnsperf`

Tests DNS query throughput and latency using `dnsperf`. Requires query list files (`internal.txt`, `external.txt`) in `dns-latency/files/`. Reports queries/sec, latency avg/max, and timeouts.

```sh
ansible-playbook dns-latency/main.yaml -i dns-latency/inventory.yaml
```

---

### `bandwidth/`
**Tools:** `iperf3`

iperf3 throughput test between hosts. Picks one host as the server (`[iperf_server]`), runs TCP, UDP, and reverse tests from all clients (`[iperf_clients]`).

```sh
ansible-playbook bandwidth/main.yaml -i bandwidth/inventory.yaml
```

Key vars in `main.yaml`:
- `duration` — seconds per test (default: 10)
- `parallel` — parallel TCP streams (default: 4)

---

### `latency-jitter/`
**Tools:** `ping`, `hping3`

Measures RTT min/avg/max/mdev and jitter (inter-packet delay variation) to a list of targets. Useful for identifying flapping links or noisy uplinks.

```sh
ansible-playbook latency-jitter/main.yaml -i latency-jitter/inventory.yaml
```

---

### `traceroute/`
**Tools:** `mtr`, `traceroute`

Path analysis to each target — maps every hop with per-hop RTT and loss %. MTR gives richer output than traceroute alone. Run from multiple VLANs to verify routing symmetry.

```sh
ansible-playbook traceroute/main.yaml -i traceroute/inventory.yaml
```

---

### `port-scan/`
**Tools:** `nmap`

TCP connect scan against a configurable list of targets and ports. Run from hosts in different VLANs to validate firewall rules from multiple vantage points.

```sh
ansible-playbook port-scan/main.yaml -i port-scan/inventory.yaml
```

> Uses `-sT` (TCP connect) not `-sS` (SYN scan) — doesn't require raw sockets, works without root on most setups.

---

### `interface-stats/`
**Tools:** `ethtool`, `ip`

NIC audit: speed, duplex, MTU, and RX/TX error/drop/overrun counters. Flags any interface with errors > 0. Useful after cable swaps, switch changes, or when diagnosing mysterious throughput degradation.

```sh
ansible-playbook interface-stats/main.yaml -i interface-stats/inventory.yaml
```

The playbook will **fail** if errors are detected (so it works as a Semaphore alert). Comment out the last task to run it as a report-only audit.

---

### `mtu-discovery/`
**Tools:** `ping` with DF bit

Probes path MTU between hosts and a list of targets. Tests multiple sizes (9000, 1500, 1492, 1472, 1420, 1280, 576) and reports which pass without fragmentation. Essential for diagnosing:
- VPN tunnel MTU mismatches
- Jumbo frame issues
- Large-file transfer failures that don't appear on small packets

```sh
ansible-playbook mtu-discovery/main.yaml -i mtu-discovery/inventory.yaml
```

---

### `arp-table/`
**Tools:** `ip neigh`, `arp`

ARP/neighbor table audit. Checks for:
- Duplicate IPs (same IP, multiple MACs — potential ARP spoofing or misconfiguration)
- FAILED/INCOMPLETE neighbor entries
- Gateway MAC consistency across all hosts (all hosts should see the same MAC)

```sh
ansible-playbook arp-table/main.yaml -i arp-table/inventory.yaml
```

---

### `connectivity-matrix/`
**Tools:** `ping`

Full-mesh connectivity test. Every host pings every other host and builds a pass/fail grid. Run after any firewall change or VLAN reconfiguration to confirm expected reachability.

```sh
ansible-playbook connectivity-matrix/main.yaml -i connectivity-matrix/inventory.yaml
```

Output example:
```
Source: proxmox-01
[ OK ] proxmox-02 (10.10.10.11)
[ OK ] proxmox-03 (10.10.10.12)
[FAIL] k3s-node-01 (10.10.20.10) — 100% packet loss
```

---

## Running in Semaphore

Each playbook can be added as a Semaphore template:
- **Repository:** this repo
- **Playbook:** `ansible/playbooks/network-tests/<name>/main.yaml`
- **Inventory:** use the per-playbook `inventory.yaml` or your global Semaphore inventory
- **Environment:** `{}`

Results are written to `/tmp/` on each target and fetched to the Semaphore runner's `/tmp/`. To persist results, add a `fetch` → local archive step or point the `results_dir` at a shared NFS path.
