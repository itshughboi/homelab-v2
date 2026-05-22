# lynis-scan

Full CIS-style security hardening audit via [Lynis](https://cisofy.com/lynis/). Produces a hardening score (0–100) with categorized findings.

## What it does

Installs Lynis, runs a full system audit on each host, and reports the hardening index score plus specific findings by severity (warning, suggestion). Alerts via ntfy if any host scores below the warning threshold (default: 65). Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/ubuntu/lynis-scan
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Quarterly, or after major infrastructure changes. Much deeper than individual SSH/user/port checks — covers kernel hardening, authentication, package management, file permissions, active services, and more.

## Thresholds

| Score | Status |
|---|---|
| ≥ 65 | OK |
| 50–64 | Warning |
| < 50 | Critical (ntfy urgent) |

A fresh Ubuntu server with the hardening playbook applied typically scores 70–80. Aim to keep it above 65.
