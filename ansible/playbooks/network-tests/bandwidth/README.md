# bandwidth

Measures network throughput between hosts using `iperf3`. Tests TCP, UDP, and reverse direction (server → client) to give a full picture of link capacity and identify asymmetric bottlenecks.

## Tool: iperf3

`iperf3` is the standard network throughput testing tool. It runs a client/server pair: the server listens, the client connects and pushes as much data as possible for a set duration, then reports the measured bitrate.

Installed automatically via apt.

## How it works

The playbook picks one host from the `[iperf_server]` inventory group as the server and runs clients from all hosts in `[iperf_clients]`. Three tests run per client:

1. **TCP** — measures sustained throughput with parallel streams
2. **UDP** — sends at a target rate (1 Gbps) and measures actual throughput + loss
3. **Reverse TCP** — server sends to client (tests the other direction of the link)

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Edit `inventory.yaml` to set one host as `iperf_server` — it should not also be in `iperf_clients`.

Key vars in `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `duration` | `10` | Seconds per test |
| `parallel` | `4` | Parallel TCP streams |

For a quick check use `duration: 5`. For a proper baseline use `duration: 30`.

## Results

Results are fetched to `/tmp/iperf3-results/<hostname>.txt` on the controller.

**Healthy TCP output (1 Gbps link, 4 streams):**

```
[ ID] Interval           Transfer     Bitrate         Retr
[SUM]  0.00-10.00 sec  1.09 GBytes   939 Mbits/sec    0     sender
[SUM]  0.00-10.00 sec  1.09 GBytes   937 Mbits/sec         receiver
```

**Healthy UDP output:**

```
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total
[  5]  0.00-10.00 sec  1.09 GBytes   938 Mbits/sec   0.022 ms  0/795506 (0%)
```

**What to look for:**

| Metric | Healthy (1G link) | Investigate |
|---|---|---|
| TCP bitrate | 900–950 Mbits/sec | < 700 Mbits/sec |
| UDP loss | 0% | > 0.1% |
| UDP jitter | < 1 ms | > 5 ms |
| Retransmits (Retr) | 0 | > 10 |
| TCP vs reverse gap | < 5% difference | Large gap = asymmetric issue |

**Signs of trouble:**
- Low TCP bitrate with high retransmits → packet loss on the link (bad cable, overloaded switch port)
- Good TCP but poor UDP loss → switch buffer/QoS issue
- Forward vs reverse significantly different → duplex mismatch or one-directional congestion
- Bitrate drops mid-test → thermal throttling or link instability
