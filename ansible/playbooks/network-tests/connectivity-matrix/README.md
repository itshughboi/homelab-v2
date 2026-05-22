# connectivity-matrix

Full-mesh ICMP reachability test. Every host in the inventory pings every other host and reports a pass/fail grid. The final play compiles all results into a single summary and fails the run if any pair is unreachable.

Used to validate firewall rules, VLAN segmentation, and routing — particularly after network changes when you need to quickly confirm that expected reachability is intact and unexpected paths are blocked.

## Tool: ping

No extra tools required — uses the standard `ping` binary present on all Linux hosts.

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Add every host you want in the matrix to the inventory. The playbook builds the target list dynamically from the inventory — no manual target configuration needed.

Key vars:

| Var | Default | Description |
|---|---|---|
| `ping_count` | `5` | Packets sent to each target |
| `ping_timeout` | `2` | Per-packet timeout in seconds |

For a faster run reduce `ping_count` to 3. For a more reliable result increase to 10.

## Results

Per-host results are fetched to `/tmp/connectivity-matrix/<hostname>.txt`. A compiled summary prints at the end of the playbook run.

**Healthy per-host output:**

```
===== Connectivity Matrix =====
Source: proxmox-01 (10.10.10.10)
Timestamp: 2026-05-19T10:00:00+0000

[ OK ] proxmox-02 (10.10.10.11)
[ OK ] proxmox-03 (10.10.10.12)
[ OK ] k3s-node-01 (10.10.20.10)
[ OK ] k3s-node-02 (10.10.20.11)
```

**With a failure:**

```
[ OK ] proxmox-02 (10.10.10.11)
[ OK ] proxmox-03 (10.10.10.12)
[FAIL] k3s-node-01 (10.10.20.10) — 100% packet loss
[FAIL] k3s-node-02 (10.10.20.11) — 100% packet loss
```

**Final summary:**

```
TOTAL: 16 OK, 4 FAIL
```

The playbook fails at the end if any `[FAIL]` entries are found, making it work as a Semaphore alert.

## Running from multiple vantage points

The value of this playbook comes from running it with different inventory files that reflect your VLAN topology:

**`inventory-management.yaml`** — all hosts on your management VLAN. Expect full mesh reachability.

**`inventory-segmented.yaml`** — mix of VLANs (management + IoT + guest). Expect some pairs to fail. Verify the failures match your firewall intent.

To run against a specific inventory:
```sh
ansible-playbook main.yaml -i inventory-segmented.yaml
```

## What to look for

| Pattern | Meaning |
|---|---|
| One host fails to reach all others | That host has a routing or NIC issue |
| All hosts fail to reach one host | That host is down, firewalled, or on wrong VLAN |
| Failures are symmetric (A↔B both fail) | Firewall/VLAN blocking between the two |
| Failure is asymmetric (A→B fails, B→A OK) | Asymmetric firewall rule or route |
| Failures only cross a VLAN boundary | Expected if firewall rules are correct; unexpected otherwise |

**Signs of trouble:**
- Newly added host fails to reach everyone → not on the right VLAN, or default gateway not set
- Previously passing pair now fails after a switch change → VLAN assignment changed on a port
- Intermittent failures (some runs OK, some fail) → packet loss on the link — run latency-jitter playbook to confirm
- Asymmetric failures → stateful firewall returning traffic on a different interface than it arrived on
