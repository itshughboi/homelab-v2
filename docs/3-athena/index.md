# 3. Athena

Athena (10.10.10.8) is the management plane — the VM that replaces your laptop as the control center. The Git server, Ansible UI, and DNS run here. (The reverse proxy / Traefik and the password manager run on **dock-prod**, not Athena.)

---

## What Runs Here

| Service | Purpose | URL |
| --- | --- | --- |
| Docker | Container runtime for the management services | — |
| Gitea | Self-hosted Git — source of truth for all IaC; GitHub is a push mirror | https://gitea.hughboi.cc |
| Semaphore | Ansible Web UI + scheduler — runs all playbooks from here | https://semaphore.hughboi.cc |
| Bind9 | Authoritative LAN DNS — `network_mode: host`, resolves `*.hughboi.cc` internally | 10.10.10.8:53 |

> [!NOTE]
> Bind9 runs with `network_mode: host` so it gets the stable host IP `10.10.10.8` directly.
> This is why it can't run in k3s — pod IPs change. The host IP is what every VLAN points to as their DNS server.

### The Handoff Model

```
Day 0: Laptop runs Ansible against Athena
Day 1: Semaphore on Athena runs all future Ansible
       Laptop retired — never needed again

Code changes → push to Gitea
Infrastructure changes → Semaphore triggers playbooks  
Secret changes → SOPS encrypted, pushed to Gitea
```

---

## Bootstrap Athena

Run from your laptop (before Semaphore exists):

```sh
ansible-playbook ansible/playbooks/ubuntu/setup-athena/main.yaml \
  -i ansible/playbooks/ubuntu/setup-athena/inventory.yaml
```

This installs Docker, OpenTofu, SOPS, age, and all management services on Athena. After it completes, Semaphore is the operator.

---

## SOPS + Age (Secrets Before Anything Else)

The full SOPS + Age workflow (`.sops.yaml`, encrypt/decrypt, what gets encrypted) is documented
once in [8-gitops/Secrets_SOPS.md](../8-gitops/Secrets_SOPS.md). The **Athena-specific** points:

> [!IMPORTANT]
> **Run `age-setup.sh` on Athena, not your laptop.** The private key must live on the machine
> that decrypts secrets at runtime — Athena, since Semaphore runs all playbooks there. Running
> it on your laptop means Semaphore can't decrypt anything. The `setup-athena` playbook installs
> `age` for you.

SSH into Athena after `setup-athena` completes, then run `./scripts/age-setup.sh` from the repo
clone. It generates the keypair (`~/.config/sops/age/keys.txt`), patches `.sops.yaml`, and tells
you to commit the **public** key.

> [!DANGER]
> **Back up the private key off-box immediately** — losing it makes every encrypted secret
> permanently unreadable. (You keep it printed + in a cloud password vault — good.)
> And if a plaintext secret ever touches Git history, assume it's compromised → rotate it.

---

## Bind9 DNS — Terraform Integration

Terraform can auto-create a DNS record for each provisioned VM via TSIG, so DNS is declarative
and rebuildable. Full setup (TSIG keygen, `update-policy`, `rndc sync`, the Terraform run) is in
[Terraform Bind9.md](Terraform%20Bind9.md).

Handy Athena-side check — query Bind9 directly, bypassing AdGuard (useful when DNS seems broken):

```sh
dig @10.10.10.8 proxmox.hughboi.cc
```

---

## Git Handoff to Gitea

```sh
git remote add gitea https://gitea.hughboi.cc/hughboi/homelab.git
git push gitea main
```

GitHub is a push mirror (auto-synced from Gitea). GitHub links in docs are valid and intentional — Gitea is primary.

---

## Semaphore Setup

Access at `https://semaphore.hughboi.cc`. After first login:

1. **Key Store** → Add SSH key (`~/.ssh/id_ed25519` private key)
2. **Repositories** → Add repository → point to Gitea repo URL
3. **Inventory** → Add inventory → path: `ansible/inventories/`
4. **Environment** → Add environment → `{}`
5. **Task Templates** → create templates for each playbook

From here, all Ansible runs through Semaphore. The laptop never needs to SSH anywhere again.

---

## Ansible Playbook Reference

See [`Ansible.md`](Ansible.md) for the operating model. Key playbooks (paths under
`ansible/playbooks/`):

| Playbook | Path | Purpose |
| --- | --- | --- |
| setup-athena | `ubuntu/setup-athena` | Initial Athena setup (run from laptop, Day 0) |
| new-host-bootstrap | `ubuntu/new-host-bootstrap` | Harden and configure any new VM |
| cluster-update | `proxmox/cluster-update` | Update Proxmox cluster config |
| network-setup | `proxmox/network-setup` | Configure VLAN bridge interfaces (vmbrX.20/.40) |
| proxmox-node-setup | `proxmox/proxmox-node-setup` | Add/configure a node in the Proxmox cluster |
| vm-template-refresh | `proxmox/vm-template-refresh` | Rebuild Template 9999 |
| k3s (new) | `kubernetes/k3s/new` | Install/reinstall k3s cluster |

---

## Pocket ID (OIDC / SSO)

Pocket ID is a lightweight OIDC provider that enables SSO across Proxmox, Gitea, Semaphore, and other services — one login for everything.

Set up after Athena is running. See [`../6-docker/Pocket ID - Proxmox.md`](../6-docker/Pocket%20ID%20-%20Proxmox.md) for configuration.

---

## Security Notes

- Traefik runs on **dock-prod** (bound to `10.10.10.10`, not `0.0.0.0`) and reverse-proxies to Athena's services over the network — Athena does not run Traefik. See [6-docker/index.md](../6-docker/index.md).
- `DOCKER-USER` iptables chain is used for host-level firewall rules that Docker can't bypass.
- Never run Docker services with `--network=host` unless strictly necessary (Bind9 is the deliberate exception).
- Web UIs are only reachable from VLAN 10 (Management) — never exposed to WAN.
