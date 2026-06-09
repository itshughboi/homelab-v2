---
title: "Ansible"
---

> [!WARNING] **DEPRECATED** — Ansible-based UniFi network management was evaluated but not adopted. Current approach: configure UniFi manually once; see the active Ansible playbooks in `ansible/playbooks/unifi/` for config sync only.

### Ansible vs Terraform
- Terraform is a source of truth whereas Ansible is saying, apply these changes if not met
- When I have a problem with Unifi, If i was using Terraform I need to debug if it's:
	- Unifi Controller, 
	- Unifi API, 
	- Terraform Provider,
	- Terraform file. 
- Management can become a nightmare if I want to do anything in the Unifi UI as I have to retroactively apply that to my terraform file to make sure 'drift' doesn't happen.

### Ansible Flow
1. Configure Unifi manually and create a management network + provisioning network with netboot options.
2. Once I provision my athena ansible machine, let it create the rest of the networks, assign IPs, etc. I can do changes in either the UI or Ansible as Ansible will skip anything that is already set.
	1. In this setup, Unifi is authoritative instead of Terraform


