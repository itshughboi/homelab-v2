## NetFlow

Settings → System → Network Monitoring → NetFlow / IPFIX

NetFlow records connection metadata — source IP, destination IP, protocol, bytes transferred, duration — for every flow through the gateway. It does **not** capture packet content.

**What it gives you:**
- Traffic visibility per VLAN (who's talking to what, how much bandwidth)
- Security: detect beaconing (IoT device phoning home every 5 minutes), lateral movement, unusual port usage
- Post-incident forensics: reconstruct what happened even after logs roll over

**Collector options (you need one, otherwise there's nothing to send to):**
| Collector | Best for |
| --- | --- |
| ntopng CE (free) | Traffic visualization, per-host/VLAN dashboards |
| nfdump / nfcapd | Raw capture + CLI queries |
| Wazuh (with NetFlow plugin) | Correlation with SIEM events |
| Graylog + NetFlow plugin | If you run Graylog already |

**Recommendation:** Enable it and point at ntopng or Wazuh. Without a collector it's useless, so don't enable until the collector is up.

- Protocol: IPFIX (preferred) or NetFlow v9
- Collector port: typically UDP 2055 (ntopng default) or 9995

### WAN Speed Test → Grafana

UniFi's built-in speed test doesn't export results to external systems directly. Two options:

**Option A — unpoller (UniFi Poller):** Polls the UniFi controller API and exports general network metrics (throughput, client counts, switch stats) to InfluxDB or Prometheus. Prebuilt Grafana dashboards exist. Does not export scheduled speed test results specifically.

**Option B (simpler) — standalone speedtest container:** Run a `speedtest-cli` or LibreSpeed container on a cron schedule that writes results directly to your InfluxDB. Completely independent of UniFi, easy to dashboard in Grafana. This is the lower-effort path if you just want WAN speed over time.

---

## Activity Logging — Syslog

Settings → System → Logging

### Where to send it: Wazuh (not CrowdSec)

**Send UniFi syslog to Wazuh.**

- **Wazuh** is a SIEM — aggregates logs from many sources, runs correlation rules, and alerts. It has built-in decoders for UniFi/firewall syslog. It can correlate a firewall block on an IP with a failed SSH attempt on the same IP across your other hosts. This is the right target for network appliance logs.
- **CrowdSec** is a collaborative IPS — parses application-layer logs (nginx, traefik, SSH auth) to detect attack patterns. Better suited to individual servers, not the gateway syslog directly.

### Wazuh does NOT auto-block on its own

Wazuh is detection and alerting only. It cannot push a block rule into UniFi or add an IP to CrowdSec by itself.

It does have **Active Response** — a feature that runs a shell script on the Wazuh manager when an alert fires. You can wire that script to call `cscli decisions add --ip <X>`, which feeds into CrowdSec's decision list and gets picked up by the UniFi bouncer. That's custom work but not complex.

### The piece that actually auto-blocks in UniFi: CrowdSec UniFi Bouncer

CrowdSec has a first-party bouncer that reads its decision list and pushes block rules directly into UniFi's firewall automatically. This is the closing link in the chain.

```
UniFi syslog ──────────────────────► Wazuh (SIEM — visibility, correlation, alerts)
                                           │
                                           └─ Active Response script (optional)
                                                      │
pve-srv SSH/auth logs ─────────────► CrowdSec ────────┴──► decisions list
traefik access logs ───────────────► CrowdSec                    │
                                                                  ▼
                                                     CrowdSec UniFi Bouncer
                                                                  │
                                                                  ▼
                                                     UniFi firewall block rule
```

**Summary of roles:**
| Tool | Role | Blocks UniFi? |
| --- | --- | --- |
| Wazuh | SIEM — collect, correlate, alert | No (unless Active Response wired up) |
| CrowdSec | Attack detection on server logs | Yes, via UniFi bouncer |
| CrowdSec UniFi Bouncer | Reads CrowdSec decisions → pushes to UniFi | Yes — this is the auto-block mechanism |
| Wazuh Active Response | Runs scripts on alert | Only if scripted to call CrowdSec API |

### Logging level

| Level | What it captures | Use |
| --- | --- | --- |
| Emergency / Alert / Critical | Hardware failure, severe faults | Always on |
| Error | Notable failures | Always on |
| **Warning** | Firewall blocks, auth failures, IPS alerts | **Recommended baseline** |
| Notice | Normal but significant events (connections established, etc.) | Use if you want more visibility |
| Informational | Verbose operational detail | Too noisy for SIEM |
| Debug | Everything | Troubleshooting only |

**Set to Warning.** You get firewall drops, IPS hits, and auth failures without flooding Wazuh with routine operational noise. Bump to Notice temporarily when investigating an issue.

> [!IMPORTANT]
> Syslog level is separate from **per-rule logging**. Ensure DENY rules in the firewall have logging enabled — blocked traffic will then appear in syslog regardless of the global level.

### Syslog forwarding config

Settings → System → Logging → Remote Logging:
- Protocol: UDP (standard) or TCP (more reliable, use if Wazuh supports it)
- Port: 514 (syslog default) or your Wazuh syslog listener port
- Destination: Wazuh manager IP

---

## Data Retention

Settings → System → Maintenance → Data Retention

**Yes, increase it.** Default retention is short and you lose forensic history fast.

| Data type | Recommended retention |
| --- | --- |
| Flow / connection records | 90 days |
| Events and alerts | 180 days |
| IPS / threat events | 180 days |

> [!NOTE]
> Local UniFi retention is the short-term buffer. Long-term storage lives in Wazuh.
> Size the controller VM's disk accordingly — flow data at 90 days can grow significantly
> on a busy network. Monitor disk usage on dock-prod (10.10.10.10) after enabling.
