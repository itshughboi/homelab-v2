# mtu-discovery

Discovers the path MTU (maximum transmission unit) between each host and a set of targets by probing at multiple packet sizes with the Don't Fragment (DF) bit set. Essential for diagnosing silent packet loss that only affects large transfers — a symptom of MTU mismatches that is easy to misdiagnose as application or TCP issues.

## Tool: ping with DF bit

No extra tool required — uses the standard `ping` binary with `-M do` (Linux) to set the DF bit, and `-s` to control payload size. The OS will report `Message too long` or `Frag needed` if the packet exceeds the path MTU.

The playbook probes these sizes in order:

| Size | Context |
|---|---|
| 9000 | Jumbo frames |
| 1500 | Standard Ethernet |
| 1492 | PPPoE (DSL) |
| 1472 | 1500 minus IP+ICMP headers — useful for checking ICMP overhead |
| 1420 | Typical WireGuard / OpenVPN tunnel MTU |
| 1280 | IPv6 minimum guaranteed MTU |
| 576 | Absolute minimum (RFC 791) |

## Why this matters

MTU mismatches cause a specific failure pattern: small packets (DNS queries, HTTP headers, pings) work fine but large transfers (file downloads, SSH key exchange, HTTPS pages) hang or fail silently. This is because TCP segments large payloads into chunks that exceed the path MTU, and if ICMP `Frag needed` messages are blocked by a firewall, TCP never learns the correct MSS.

Common causes:
- **VPN tunnels** — WireGuard adds ~60 bytes of overhead; if the outer MTU is 1500, the inner must be ≤1420
- **Jumbo frames misconfigured** — one switch port set to 9000, the rest at 1500
- **PPPoE uplinks** — ISP-side MTU is 1492, not 1500

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Key vars in `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `mtu_targets` | gateway, TrueNAS, 1.1.1.1 | List of `name`/`host` targets |
| `mtu_probe_sizes` | 9000, 1500, 1492... | Sizes to probe in order |

## Results

Results are fetched to `/tmp/mtu-results/<hostname>.txt` on the controller.

**Healthy output — standard 1500 MTU path:**

```
OK 1500: PING 10.10.10.1: 1472 data bytes ... 64 bytes from 10.10.10.1
FAIL 9000: ping: local error: message too long, mtu=1500
```

The largest `OK` line is your path MTU.

**Output on a WireGuard tunnel:**

```
OK 1420: PING 10.0.0.1: 1392 data bytes ... 64 bytes from 10.0.0.1
FAIL 1472: ping: local error: message too long, mtu=1420
FAIL 1500: ping: local error: message too long, mtu=1420
```

Path MTU = 1420 — correct for WireGuard. If you saw FAIL at 1420, the tunnel MTU is misconfigured.

**What to look for:**

| Scenario | Expected largest OK |
|---|---|
| Standard LAN | 1500 |
| PPPoE uplink | 1492 |
| WireGuard VPN | 1420 |
| OpenVPN (UDP) | ~1420–1450 |
| Jumbo frame network | 9000 |

**Signs of trouble:**
- Path MTU to LAN target is 1492 or lower → something between the hosts is set to PPPoE MTU, or a misconfigured bridge
- Path MTU to internet is 1280 → upstream is dropping larger packets; check ISP or intermediate firewall
- Different MTU results from different hosts to the same target → asymmetric path, or one host has a misconfigured interface MTU
- All sizes fail including 576 → firewall is blocking ICMP entirely (also breaks TCP PMTUD, which is a problem)
