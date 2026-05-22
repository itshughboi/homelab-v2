# traceroute

Maps the network path from each host to a set of targets, showing every hop with per-hop RTT and packet loss. Used to identify where latency is introduced, verify traffic takes the expected routing path, and diagnose routing asymmetry after network changes.

## Tools

**mtr** (`mtr-tiny`) — combines traceroute and ping. Sends multiple packets to each hop and builds statistics (loss %, avg/best/worst RTT) per hop. More reliable than a single traceroute because it averages out transient drops.

**traceroute** — classic single-pass path trace. Included alongside mtr for comparison; useful when a hop appears in one but not the other (indicating ICMP rate limiting).

Both installed automatically via apt.

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Key vars in `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `trace_targets` | gateway, TrueNAS, 1.1.1.1, 8.8.8.8 | List of `name`/`host` targets |
| `mtr_cycles` | `20` | Packets sent per hop |
| `mtr_interval` | `0.5` | Seconds between packets |

Run with `--no-dns` by default — speeds up output significantly. Remove it if you want hostnames resolved.

## Results

Results are fetched to `/tmp/traceroute-results/<hostname>.txt` on the controller.

**Healthy mtr output:**

```
Start: 2026-05-19T10:00:00+0000
HOST: proxmox-01                  Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 10.10.10.1                 0.0%    20    0.4   0.4   0.3   0.6   0.1
  2.|-- 192.168.1.1                0.0%    20    2.1   2.2   1.9   3.1   0.3
  3.|-- 72.14.204.1                0.0%    20    8.4   8.6   8.1   9.2   0.3
  4.|-- 1.1.1.1                    0.0%    20    9.1   9.0   8.8   9.5   0.2
```

**What to look for:**

| Signal | Meaning |
|---|---|
| Loss at a middle hop, 0% at subsequent hops | ICMP rate limiting on that router — not real loss |
| Loss at a hop that persists to destination | Real packet loss starting at that point |
| RTT spike at one hop that carries through | Latency introduced at that device |
| RTT spike at one hop that drops at the next | That hop deprioritizes ICMP — normal for transit routers |
| Path differs between two hosts to the same target | Routing asymmetry — verify it's intentional |
| Hop count changes between runs | Route flapping |

**Signs of trouble:**
- Loss at the final destination but not intermediate hops → firewall blocking ICMP, not real loss (verify with iperf or port-scan)
- RTT doubles at your ISP's first hop → buffer bloat on your uplink
- Unexpected hops (extra private IPs) → traffic leaving through an unexpected interface or VPN leaking
- mtr and traceroute disagree on path → ECMP load balancing across multiple paths
