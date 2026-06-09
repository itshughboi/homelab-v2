# Ansible & Semaphore (on Athena)

How configuration management runs in this homelab. **What** each playbook does is catalogued in
[index.md → Ansible Playbook Reference](index.md#ansible-playbook-reference); this page is the
operating model + where the config it applies is documented.

---

## Operating model

```
Day 0   Laptop runs `setup-athena` against a fresh Athena VM
Day 1+  Semaphore (on Athena) runs every playbook from then on — laptop retired
```

- Source of truth: **Gitea** (`gitea.hughboi.cc`), mirrored to GitHub.
- Runner: **Semaphore** at `https://semaphore.hughboi.cc` (setup steps in [index.md](index.md#semaphore-setup)).
- Secrets: **SOPS + Age**, decrypted at runtime on Athena — see [8-gitops/Secrets_SOPS.md](../8-gitops/Secrets_SOPS.md).
- Playbooks are idempotent — re-running skips anything already correct, so UI changes and
  Ansible runs coexist safely.

---

## What Ansible manages (and where it's documented)

Ansible applies config that's specified *elsewhere* — it doesn't re-define it. Pointers so this
page doesn't duplicate (and drift from) the network/host docs:

| Area | Playbook(s) | Spec lives in |
| --- | --- | --- |
| Proxmox bridges + VLAN sub-interfaces (`.20`/`.40`, MTU 9000) | `proxmox/network-setup` | [pve/Virtual Interfaces.md](../2-proxmox/pve/Virtual%20Interfaces.md) |
| Proxmox cluster node config | `proxmox/proxmox-node-setup` | [provisioning/README.md → Cluster](../2-proxmox/provisioning/README.md#proxmox-cluster) |
| Proxmox repos + updates | `proxmox/cluster-update` | [pve/README.md](../2-proxmox/pve/README.md) |
| New VM hardening/bootstrap | `ubuntu/new-host-bootstrap` | — |
| Athena management stack | `ubuntu/setup-athena` | [index.md](index.md) |
| k3s | `kubernetes/k3s/...` | [7-k3s/](../7-k3s/index.md) |

> VLAN definitions, IP plan, firewall, and QoS are **not** Ansible-managed here — UniFi is
> configured manually (see [1-networking/Unifi/Ansible.md](../1-networking/Unifi/Ansible.md) for
> why the UniFi-via-Ansible approach was shelved). The authoritative network tables live under
> [1-networking/](../1-networking/README.md).

---

## Bootstrap flow

1. Manually configure UniFi (VLANs + firewall) — the minimum so Athena is reachable. See
   [1-networking/](../1-networking/README.md).
2. Provision the Athena VM (Terraform clones the template) — see
   [provisioning/README.md](../2-proxmox/provisioning/README.md).
3. From the laptop, run `setup-athena` to install Docker + the management stack.
4. Set up Semaphore ([index.md](index.md#semaphore-setup)); from here all Ansible runs there.
