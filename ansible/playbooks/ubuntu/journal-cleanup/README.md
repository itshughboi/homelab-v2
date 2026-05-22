# journal-cleanup

Vacuums systemd journal logs on all hosts to prevent unbounded disk growth.

## What it does

Runs `journalctl --vacuum-size=500M --vacuum-time=30d` on each host, reports freed space, and sends an ntfy summary. Safe to run at any time — does not affect running services.

## Run

```sh
cd ansible/playbooks/ubuntu/journal-cleanup
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Weekly in Semaphore. Without this, `/var/log/journal` grows indefinitely on busy hosts (k3s nodes especially, given kubelet log volume). The defaults (500 MB, 30 days) keep the root disk safe on 20 GB VMs.
