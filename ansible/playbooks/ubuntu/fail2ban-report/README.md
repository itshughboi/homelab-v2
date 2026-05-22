# fail2ban-report

Shows active fail2ban jails, current ban counts, top attacking IPs, and recent ban activity across all hosts.

## What it does

Runs `fail2ban-client status` on each jail, collects ban counts and top offending IPs, and produces a human-readable report. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/ubuntu/fail2ban-report
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Weekly for security situational awareness. Use alongside Wazuh (which gives you a deeper threat view) — this is a quick "what's fail2ban actively blocking" check.
