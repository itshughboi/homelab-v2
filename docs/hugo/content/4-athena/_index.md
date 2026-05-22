---
title: "4. Athena"
weight: 40
bookCollapseSection: true
---

# 4. Athena

Athena (10.10.10.8) is the management plane — the VM that replaces your laptop as the control center. Everything runs here: the Git server, Ansible UI, DNS, reverse proxy, and the password manager.

---

## What Runs Here

| Service | Purpose | URL |
| --- | --- | --- |
| Docker | Container runtime for all management services | — |
| Traefik | Reverse proxy — bound to `10.10.10.8`, handles `*.hughboi.cc` for mgmt | https://traefik.hughboi.cc |
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
cd ansible/playbooks/ubuntu/
ansible-playbook bootstrap-athena.yml -i inventory.yaml
```

This installs Docker and all management services on Athena. After it completes, Semaphore is the operator.

---

## SOPS + Age (Secrets Before Anything Else)

Set this up before pushing any secrets to Git.

**Why SOPS + Age instead of Vault:** no additional service to maintain, Age is modern and simple, private key never leaves Athena. Vault is overkill for one operator.

```sh
# On Athena
apt install age sops

# Generate keypair — private key NEVER leaves Athena
age-keygen -o ~/.config/sops/age/keys.txt
# Output includes: Public key: age1...
```

Run the setup script (populates `.sops.yaml` in repo root):
```sh
./scripts/age-setup.sh
```

Or manually update `.sops.yaml`:
```yaml
creation_rules:
  - path_regex: secrets\.yaml$
    age: "<your-age-public-key>"
  - path_regex: terraform\.tfvars$
    age: "<your-age-public-key>"
```

**Encrypt / decrypt:**
```sh
sops --encrypt --in-place secrets.yaml   # encrypt file in place
sops secrets.yaml                         # open decrypted in $EDITOR
```

> [!DANGER]
> If a plaintext secret ever touches Git history, assume it is compromised.
> Rotation is required — even if you delete the file immediately.
> This applies to all secrets: API tokens, passwords, private keys.

---

## Bind9 DNS — Terraform Integration

Terraform auto-creates DNS records for each provisioned VM via TSIG authentication. This means every VM gets a DNS record automatically when `terraform apply` runs.

```sh
# Inside Bind9 container — generate TSIG key
docker exec -it bind9 tsig-keygen -a hmac-sha256
```

Save output to `/etc/bind/named.conf.key`. Add `update-policy` to zone:

```bind
zone "hughboi.cc" {
    type master;
    file "/etc/bind/zones/db.hughboi.cc";
    update-policy { grant tsig-key zonesub any; };
};
```

Apply DNS records via Terraform:
```sh
cd terraform/bind9
terraform init && terraform apply
dig proxmox.hughboi.cc @10.10.10.8   # should resolve to 10.10.10.1
```

Sync Bind9 journal to zone file (run after Terraform updates):
```sh
docker exec -it bind9 rndc sync
```

> [!DANGER]
> The TSIG key allows DNS record updates to your zone. Encrypt with SOPS before committing anywhere near Git.

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

See [`Ansible.md`](Ansible.md) for full playbook documentation. Key playbooks:

| Playbook | Path | Purpose |
| --- | --- | --- |
| bootstrap-athena | `ubuntu/bootstrap-athena` | Initial Athena setup |
| new-host-bootstrap | `ubuntu/new-host-bootstrap` | Harden and configure any new VM |
| cluster-update | `proxmox/cluster-update` | Update Proxmox cluster config |
| vm-template-refresh | `proxmox/vm-template-refresh` | Rebuild Template 9999 |
| k3s-install | `kubernetes/k3s/new` | Install/reinstall k3s cluster |
| join-cluster | `proxmox/join-cluster` | Add node to Proxmox cluster |
| virtual-interfaces | `proxmox/virtual-interfaces` | Configure VLAN bridge interfaces |

---

## Pocket ID (OIDC / SSO)

Pocket ID is a lightweight OIDC provider that enables SSO across Proxmox, Gitea, Semaphore, and other services — one login for everything.

Set up after Athena is running. See [`Terraform Bind9.md`](Terraform%20Bind9.md) and [`../7-docker/Pocket ID - Proxmox.md`](../7-docker/Pocket%20ID%20-%20Proxmox.md) for configuration.

---

## Security Notes

- Traefik is explicitly bound to `10.10.10.8` — not `0.0.0.0`. This prevents Docker from publishing ports to the wrong interface.
- `DOCKER-USER` iptables chain is used for host-level firewall rules that Docker can't bypass.
- Never run Docker services with `--network=host` unless strictly necessary (Bind9 is the deliberate exception).
- Web UIs are only reachable from VLAN 10 (Management) — never exposed to WAN.
