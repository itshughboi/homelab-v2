# Gatus Watchdog (Athena)

External uptime monitor for the k3s cluster. Runs on Athena (VLAN 10), completely independent of k3s. Alerts via Discord when the cluster or key services become unreachable.

## Why not run Gatus inside k3s?

The k3s Gatus deployment (`apps/kubernetes/k3s/apps/gatus/`) monitors your k3s services from inside the cluster — great for app-level health dashboards. But if k3s itself goes down, that Gatus instance dies with it. You'd have no visibility during the exact moment you need it most.

This watchdog runs on Athena, a separate VM that has nothing to do with k3s. Even a complete k3s cluster failure leaves this running.

## What it checks

| Check | What failure means |
|-------|--------------------|
| k3s API (`tcp://10.10.30.30:6443`) | kube-vip VIP is unreachable — cluster is down or quorum lost |
| k3s-master-1/2/3 ICMP | Individual control plane node is unreachable |
| k3s Grafana/Prometheus/ArgoCD HTTPS | Cluster is up but Traefik or ingress is broken |
| Vaultwarden, Gitea | Key services regardless of which stack they're on |
| Proxmox nodes TCP | Physical nodes are reachable |
| dock-prod, TrueNAS ICMP | Core infrastructure is up |

Failure threshold is 2 consecutive checks (2 minutes) before alerting — avoids flapping from transient blips.

## Prerequisites

Set the Discord webhook in Ansible vault:
```sh
ansible-vault edit ansible/inventories/group_vars/all.yml
# Add: vault_discord_webhook_url: "https://discord.com/api/webhooks/..."
```

## Run

```sh
cd ansible/playbooks/ubuntu/gatus-watchdog
ansible-playbook main.yaml -i ../../../inventories/hosts.ini --limit athena
```

## Check it's working

```sh
# From Athena (SSH in first)
curl http://localhost:8888/health
curl http://localhost:8888/api/v1/endpoints/statuses
```

Gatus UI is on `localhost:8888` — only accessible from Athena itself (no Traefik exposure). SSH tunnel if you want to view the dashboard:
```sh
ssh -L 8888:localhost:8888 hughboi@10.10.10.8
# Then open http://localhost:8888 in your browser
```

## Logs

```sh
docker logs gatus-watchdog -f
```
