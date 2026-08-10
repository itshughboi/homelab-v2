# compose-health

Checks the health of every Docker Compose project on dock-prod and alerts if any container is stopped, unhealthy, or restarting.

## What it does

Searches `/home/hughboi/code` for `compose.yaml` files, inspects every container in each project, and flags containers in states other than `running`. Sends an ntfy alert if any issues are found. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/docker/compose-health
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/docker/compose-health/main.yaml -l dock-prod
```

## Schedule

Run every 15–30 minutes as a Semaphore job for continuous fleet health. Use as a lightweight complement to Grafana/Prometheus for "is everything up" checks.

## Target

`docker` group, limited to `dock-prod` (`10.10.10.10`)
