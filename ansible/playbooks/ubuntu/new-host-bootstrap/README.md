# new-host-bootstrap

Goes from a fresh Ubuntu VM (cloned from template 9999) to production-ready in one run.

## What it does

1. Sets hostname and timezone
2. Installs baseline packages
3. Configures the `hughboi` user and sudo
4. Pushes SSH authorized keys
5. Hardens SSH config (no password auth, no root login)
6. Configures chrony for NTP
7. Configures UFW (deny in, allow out, allow SSH)
8. Configures fail2ban for SSH
9. Enables unattended-upgrades for security patches
10. Sets MOTD
11. Caps journald to 500 MB
12. Optionally installs Docker (`install_docker: true`)
13. Optionally joins the k3s cluster (`join_k3s: true`)

Idempotent — safe to re-run.

## Run

```sh
cd ansible/playbooks/ubuntu/new-host-bootstrap

# Edit inventory.yaml to point at the new host IP
# Edit vars to set hostname, timezone, optional flags

ansible-playbook -i inventory.yaml main.yaml
```

## Typical flow

```
terraform apply          # create VM from template 9999
→ new-host-bootstrap     # configure the VM
→ whatever service playbook is needed
```

## Notes

- Assumes SSH key is already accepted (Terraform injects it via cloud-init on the template)
- If the host isn't yet in your SSH known_hosts: `ssh-keyscan <ip> >> ~/.ssh/known_hosts`
