# interface-stats

Audits NIC interface health on each host: link speed, duplex mode, MTU, and error/drop/overrun counters. Flags any interface with non-zero errors so the playbook can be used as a scheduled health check in Semaphore.

## Tools

**ethtool** — reads NIC driver information: negotiated link speed, duplex mode, autoneg status, and whether the cable is physically connected.

**ip** (`iproute2`) — reads kernel interface stats: TX/RX bytes, errors, drops, overruns, carrier errors.

**`/proc/net/dev`** — kernel counter file, parsed directly for raw error counts.

All installed automatically via apt (ethtool may already be present).

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

No required configuration — the playbook auto-discovers physical interfaces (filters out loopback, Docker, veth, bridge, tun/tap).

Key var:

| Var | Default | Description |
|---|---|---|
| `expected_speed` | `1000` | Flag interfaces not at this Mbps |

The last task in the playbook **fails** if errors are detected. This is intentional — it makes it work as a Semaphore alert. Comment it out if you want a report-only run:

```yaml
# - name: Fail playbook if errors detected
#   fail: ...
```

## Results

Results are fetched to `/tmp/interface-stats/<hostname>.txt` on the controller.

**Healthy error check output:**

```
── Error / Drop Summary ──────────────────────────
OK: No errors or drops detected on any interface
```

**Unhealthy — errors detected:**

```
── Error / Drop Summary ──────────────────────────
INTERFACES WITH ERRORS OR DROPS:
  !! ens18: RX_err=0 RX_drop=0 RX_over=0 TX_err=142 TX_drop=0
```

**Healthy ethtool output:**

```
Settings for ens18:
        Speed: 1000Mb/s
        Duplex: Full
        Auto-negotiation: on
        Link detected: yes
```

**Unhealthy ethtool output — autoneg mismatch:**

```
Settings for ens18:
        Speed: 100Mb/s        ← should be 1000
        Duplex: Half          ← half duplex causes collisions under load
        Auto-negotiation: on
        Link detected: yes
```

**What to look for:**

| Counter | Healthy | Investigate |
|---|---|---|
| RX errors | 0 | Any — bad cable, NIC hardware fault |
| TX errors | 0 | Any — driver issue, switch port fault |
| RX drops | 0 | Any — buffer overflow, CPU can't keep up |
| RX overruns | 0 | Any — ring buffer full, IRQ saturation |
| Speed | 1000 Mbps | 10 or 100 Mbps — autoneg failed, old cable |
| Duplex | Full | Half — will cause collisions and high retransmit rate |

**Signs of trouble:**
- TX errors increasing over time → swap the cable first, then try a different switch port
- RX drops without errors → host CPU is overwhelmed processing packets (check IRQ affinity)
- Speed negotiated at 100M → check cable category (needs Cat5e+), try forcing speed with ethtool
- Half duplex → almost always a bad or missing autoneg setting on the switch port
