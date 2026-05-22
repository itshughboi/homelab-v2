# port-scan

Checks TCP port reachability from each host to a configurable list of targets and ports. Used to validate firewall rules, verify services are listening on expected ports, and audit network exposure — particularly after VLAN or firewall changes.

## Tool: nmap

`nmap` is the standard network port scanner. This playbook uses TCP connect scan (`-sT`) which completes the full three-way handshake — no raw socket privileges required, works from any host, and is unambiguous (open = service accepted the connection).

Installed automatically via apt.

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

The key insight is **where you run from**. Run this playbook from hosts in different VLANs to validate that firewall rules are actually enforced from the correct vantage points:

- Run from your management VLAN → verify you can reach everything you should
- Run from an IoT or guest VLAN → verify you cannot reach management hosts
- Run from a k8s node → verify pod network doesn't have unexpected access to host services

Key vars in `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `scan_targets` | gateway, Proxmox, TrueNAS, Docker host | List of `name`/`host`/`ports` targets |
| `nmap_flags` | `-sT -T4 --open` | Scan type, timing, show open only |

To add a target:
```yaml
scan_targets:
  - name: k3s_api
    host: 10.10.20.1
    ports: "6443,443,80"
  - name: truenas_smb
    host: 10.10.10.5
    ports: "445,139"
```

## Results

Results are fetched to `/tmp/nmap-results/<hostname>.txt` on the controller.

**Healthy output (port is open and expected):**

```
Nmap scan report for 10.10.10.10
Host is up (0.00041s latency).

PORT     STATE SERVICE
22/tcp   open  ssh
8006/tcp open  http-alt

Nmap done: 1 IP address (1 host up) scanned in 0.05 seconds
```

**Port is closed (service not running or wrong port):**

```
PORT     STATE  SERVICE
8006/tcp closed http-alt
```

**Port is filtered (firewall blocking):**

```
PORT     STATE    SERVICE
8006/tcp filtered http-alt
```

**What to look for:**

| State | Meaning |
|---|---|
| `open` | Service accepted the connection |
| `closed` | Host is up, but nothing is listening on that port |
| `filtered` | Firewall is dropping or rejecting packets — no response |
| Host not found / down | ICMP blocked or host offline — check with ping first |

**Key distinction — closed vs filtered:**
- `closed` means the host responded with RST — it's reachable, service just isn't running
- `filtered` means no response (or ICMP unreachable) — a firewall rule is blocking it

If you expect a port to be open but it shows `filtered`, the firewall is working but the service may also not be running — use SSH to verify the service is up separately.
