# latency-jitter

Measures round-trip latency and jitter (inter-packet delay variation) from each host to a configurable list of targets. Useful for diagnosing flapping links, noisy uplinks, or QoS issues that cause variable delay without causing outright packet loss.

## Tools

**ping** (`iputils-ping`) — sends ICMP echo requests and measures round-trip time. Reports min/avg/max/mdev over N packets. The `mdev` (mean deviation) value is a basic jitter measure.

**hping3** — low-level packet crafter used here in ICMP mode. With a fixed inter-packet interval, the variance in response timing reveals jitter more precisely than ping's summary statistics.

Both installed automatically via apt.

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Key vars in `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `ping_targets` | gateway, DNS, 8.8.8.8, 1.1.1.1 | List of `name`/`ip` targets |
| `ping_count` | `50` | ICMP packets per target |
| `hping_count` | `20` | hping3 packets per target |
| `hping_interval` | `u10000` | Inter-packet interval (u = microseconds, 10000 = 10ms) |

To add targets, extend `ping_targets`:
```yaml
ping_targets:
  - name: truenas
    ip: 10.10.10.5
  - name: k3s_vip
    ip: 10.10.20.1
```

## Results

Results are fetched to `/tmp/latency-results/<hostname>.txt` on the controller.

**Healthy ping output:**

```
--- 10.10.10.1 ping statistics ---
50 packets transmitted, 50 received, 0% packet loss, time 49056ms
rtt min/avg/max/mdev = 0.212/0.341/0.891/0.098 ms
```

**Healthy hping3 output:**

```
--- 10.10.10.1 hping statistic ---
20 packets transmitted, 20 packets received, 0% packet loss
round-trip min/avg/max = 0.2/0.3/0.9 ms
```

**What to look for:**

| Metric | Healthy (LAN) | Investigate |
|---|---|---|
| Packet loss | 0% | Any loss to LAN targets |
| avg RTT (LAN) | < 1 ms | > 5 ms |
| avg RTT (internet) | < 20 ms | > 80 ms |
| mdev / jitter (LAN) | < 0.5 ms | > 2 ms |
| mdev / jitter (internet) | < 5 ms | > 20 ms |
| max − avg gap | Small | Large gap = intermittent spikes |

**Signs of trouble:**
- `mdev` high but avg acceptable → jitter without sustained latency — often QoS, buffer bloat, or a flapping link
- Loss to LAN targets only → switch or VLAN issue
- Loss to internet but not gateway → upstream provider problem
- One host has high latency to everything → NIC driver, duplex mismatch, or overloaded CPU
