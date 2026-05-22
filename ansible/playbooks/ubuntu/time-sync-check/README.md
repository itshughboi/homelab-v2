# time-sync-check

Verifies NTP time synchronization status across all hosts and alerts on excessive drift.

## What it does

Checks that chrony or systemd-timesyncd is active and synchronized, then measures current drift. Sends ntfy alert if drift exceeds the threshold.

| Drift | Status |
|---|---|
| < 500 ms | OK |
| 500 ms – 2 s | Warning |
| > 2 s | Critical |

## Run

```sh
cd ansible/playbooks/ubuntu/time-sync-check
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Daily. Why this matters for k3s:
- k3s cluster operations start failing with drift above ~2 seconds (etcd uses time for consensus)
- TLS certificate validation fails with large drift
- Prometheus metric timestamps become unreliable

Drift spikes can happen after a VM live-migration or host power event when the VM clock doesn't resync quickly.
