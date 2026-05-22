# disk-health

SMART health check on all physical drives across all hosts. Catches failing drives before they fail completely.

## What it does

Installs `smartmontools` if missing, runs `smartctl -a` on every non-virtual disk, and checks:
- Overall SMART health status
- Reallocated sectors, pending sectors, uncorrectable errors
- Drive temperature (warns at 50°C, critical at 60°C)

Sends ntfy alert if any drive shows degraded status or warning signs.

## Run

```sh
cd ansible/playbooks/ubuntu/disk-health
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Weekly in Semaphore. TrueNAS and PBS also have their own SMART monitoring — this covers the k3s nodes and Athena which don't have dedicated storage monitoring.
