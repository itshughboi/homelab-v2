# arp-table

Dumps and audits the ARP (Address Resolution Protocol) neighbor table on each host. Checks for duplicate IP-to-MAC mappings (potential ARP spoofing or IP conflicts), stale/failed entries, and verifies that all hosts see the same MAC address for the gateway.

## Tools

**ip neigh** (`iproute2`) — the modern Linux neighbor table interface. Shows all ARP entries with their state (REACHABLE, STALE, FAILED, INCOMPLETE).

**arp -n** (`net-tools`) — legacy ARP table view. Included for cross-reference since some entries appear differently between tools.

**arping** — used to force ARP resolution (flush + re-probe) so the table reflects current state rather than cached stale entries.

All installed automatically via apt.

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Key var:

| Var | Default | Description |
|---|---|---|
| `gateway_ip` | `10.10.10.1` | Gateway IP to check MAC consistency for |

The playbook flushes stale entries and pings the gateway before reading the table to ensure the most relevant entries are current.

## Results

Results are fetched to `/tmp/arp-results/<hostname>.txt` on the controller. A cross-host gateway MAC consistency check runs at the end from localhost.

**Healthy per-host output:**

```
── Conflict / Integrity Check ────────────────────
OK: No duplicate IP/MAC mappings
OK: No failed neighbors

── Gateway MAC ──────────────────────────────────
10.10.10.1 -> aa:bb:cc:dd:ee:ff

── Full Neighbor Table (ip neigh) ───────────────
10.10.10.1 dev ens18 lladdr aa:bb:cc:dd:ee:ff REACHABLE
10.10.10.5 dev ens18 lladdr 11:22:33:44:55:66 REACHABLE
10.10.10.11 dev ens18 lladdr 77:88:99:aa:bb:cc STALE
```

**Healthy gateway MAC consistency check:**

```
ok: [localhost] => {
    "msg": "OK: All hosts see the same gateway MAC"
}
```

**Unhealthy — duplicate IP detected:**

```
!! DUPLICATE IP/MAC MAPPINGS DETECTED:
   10.10.10.1 -> {'aa:bb:cc:dd:ee:ff', '11:22:33:44:55:66'}
```

Two different MACs are responding for the gateway IP. This is either:
- ARP spoofing (someone is poisoning the ARP table)
- A legitimate failover (VRRP/HSRP keeps-alive with a virtual MAC)
- An IP conflict (two devices configured with the same IP)

**Unhealthy — failed neighbors:**

```
!! FAILED/INCOMPLETE NEIGHBORS:
   10.10.10.5 dev ens18  FAILED
```

A neighbor was in the ARP table but is no longer responding. It's powered off, its IP changed, or there's a routing/VLAN issue.

**What to look for:**

| State | Meaning |
|---|---|
| `REACHABLE` | Entry is current and verified |
| `STALE` | Not recently verified but still usable — normal for inactive hosts |
| `FAILED` | Host is no longer responding — investigate |
| `INCOMPLETE` | ARP request sent but no reply — host unreachable or VLAN issue |
| `PERMANENT` | Static ARP entry |

**Signs of trouble:**
- Multiple MACs for the same IP → IP conflict or ARP spoofing; isolate with `arping -D <ip>`
- Gateway MAC differs between hosts → one host is being ARP-poisoned, or there was a failover event and one host hasn't updated
- Many FAILED entries → devices have been moved or powered off, or a VLAN was reconfigured
- Gateway shows FAILED → routing is broken from that host even if the link is up
