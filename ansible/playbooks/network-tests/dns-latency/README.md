# dns-latency

Tests DNS server query throughput and response latency using `dnsperf`. Runs a sustained query load against your DNS server and reports queries/sec, average latency, and timeout rate.

## Tool: dnsperf

`dnsperf` sends DNS queries at a controlled rate and measures how many succeed, how fast, and how many time out. It's the standard tool for DNS load testing — used to benchmark resolvers, detect degradation under load, and compare performance before/after config changes.

Installed automatically via apt.

## Query files

Place query list files in `dns-latency/files/`. Each line is a domain + record type:

```
google.com A
github.com A
cloudflare.com AAAA
homelab.local A
proxmox.local A
```

The playbook ships with two files:
- `internal.txt` — internal/local domain queries (tests your resolver's cache and local zone performance)
- `external.txt` — external domain queries (tests upstream forwarding performance)

## Usage

```sh
ansible-playbook main.yaml -i inventory.yaml
```

Key vars at the top of `main.yaml`:

| Var | Default | Description |
|---|---|---|
| `dns_server` | `10.10.10.10` | DNS server to test |
| `test_duration` | `30` | Seconds to run each test |
| `qps` | `1` | Queries per second |

Increase `qps` to stress-test. Start at 1 for a baseline, then try 10, 50, 100 to find where the server starts dropping queries.

## Results

Results are saved to `/tmp/dnsperf-results/` on each host and named `<hostname>-<testfile>.txt`.

**Healthy output:**

```
DNS Performance Testing Tool
...
Statistics:

  Queries sent:         30
  Queries completed:    30 (100.00%)
  Queries lost:         0 (0.00%)

  Response codes:       NOERROR 30 (100.00%)
  Average packet size:  request 28, response 56
  Run time (s):         30.001
  Queries per second:   1.000

  Average latency (s):  0.002145
  Minimum latency (s):  0.001203
  Maximum latency (s):  0.004821
  Std deviation (s):    0.000612
```

**What to look for:**

| Metric | Healthy | Investigate |
|---|---|---|
| Queries lost | 0% | > 1% |
| Average latency | < 5ms (local), < 50ms (upstream) | > 20ms local, > 100ms upstream |
| Max latency | < 50ms | > 200ms (timeouts or upstream issues) |
| SERVFAIL responses | 0 | Any — indicates resolver error or unreachable upstream |

**Signs of trouble:**
- High loss % at low QPS → resolver is struggling even under light load
- Large gap between avg and max latency → intermittent upstream timeouts
- Internal queries slower than external → local zone or cache issue
