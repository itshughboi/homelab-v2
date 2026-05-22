# Ansible Playbooks

Organized by function. All playbooks use the shared inventory at `../../inventories/hosts.ini`.

## Directory Overview

| Directory | Purpose |
|-----------|---------|
| [ubuntu/](ubuntu/) | Base OS setup — hardening, core packages, updates, SSH keys, reboots |
| [kubernetes/k3s/](kubernetes/k3s/) | k3s cluster install scripts |
| [kubernetes/rke2/](kubernetes/rke2/) | RKE2 cluster Ansible roles |
| [docker/](docker/) | Docker install, Docker Swarm, Traefik + Portainer deploy |
| [proxmox/](proxmox/) | Proxmox node configuration |
| [unifi/](unifi/) | Unifi network provisioning — interfaces, networking roles |
| [vaultwarden/](vaultwarden/) | Vaultwarden SQLite backup + backup validation |
| [netbootxyz-bootstrap/](netbootxyz-bootstrap/) | Configure netboot.xyz for PXE booting |
| [network-tests/](network-tests/) | DNS latency testing playbooks |

---

### Using Playbooks
```
ansible-playbook PLAYBOOKNAME -i inventory.yaml --private-key ~/.ssh/ansible --ask-become-pass
```
###### **inventory.yaml**: relative path to the inventory the playbook will use
###### **private-key**: If inventory has [all:vars} specifying key file, you can omit this
###### **ask-become-pass**: when a sudo command runs and a password is required on the user you are running sudo on, you may need this sometimes to run the playbook


#### .cfg file
- if using a ansible.cfg file, that specifies where the inventory file is so all you have to do is this:
```
ansible-playbook playbook-file-name.yaml
```

Example ansible.cfg
```
[defaults]
roles_path = ./roles
inventory = ./inventory.ini
host_key_checking = False
```
