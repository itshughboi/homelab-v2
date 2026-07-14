# 3. Athena

Athena (10.10.10.8) is the management plane — the VM that replaces your laptop as the control center. The Git server, Ansible UI, and DNS run here. (The reverse proxy / Traefik and the password manager run on **dock-prod**, not Athena.)

> ▸ **Build order:** [BUILD.md](../BUILD.md) **Phase 3 (Athena)** — after storage; before Docker/k3s.

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

This installs Docker, OpenTofu, SOPS, age, and all management services on Athena — including the
**Loki Docker logging driver plugin**, which every app in `apps/docker/*/compose.yaml` requires
(`logging: driver: loki`). After it completes, Semaphore is the operator.

> [!WARNING]
> **If you ever run `docker compose up` on Athena manually** (outside this playbook — e.g. bringing
> up a single app by hand), and the plugin isn't installed yet, you'll hit:
> `error looking up logging plugin loki: plugin "loki" not found`. Fix once with:
>
> ```sh
> sudo docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
> ```
>
> This bit us cutting bind9 over from a loose dock-prod-era deploy to the repo's compose file —
> the plugin had only ever been installed on dock-prod, never on Athena.

> [!WARNING]
> **Pin Athena's own DNS resolver to bind9 explicitly — DHCP-supplied server order isn't reliable.**
> Athena gets `10.10.10.8, 10.10.10.10, 9.9.9.9` from DHCP with no explicit preference, and
> systemd-resolved doesn't consistently pick `10.10.10.8` (itself/bind9) as `Current DNS Server` —
> it picked `9.9.9.9` (Quad9) in practice, which obviously can't resolve internal-only hostnames
> like `gitea.hughboi.cc`. This breaks anything on Athena doing a plain hostname lookup (git, curl,
> etc.) with a confusing "does not have any RR of the requested type" error, even though
> `dig @10.10.10.8 <host>` (bypassing the system resolver) works fine the whole time.
>
> Fix by adding an explicit `nameservers:` block to Athena's netplan config
> (`/etc/netplan/*.yaml`), forcing bind9 first regardless of DHCP order:
>
> ```yaml
>       nameservers:
>         addresses:
>           - 10.10.10.8
>           - 9.9.9.9
> ```
>
> Then `sudo netplan apply`. Verify with `resolvectl status eth0` — `Current DNS Server` should
> show `10.10.10.8`.

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

From your laptop or any other client, `origin` should point at Gitea directly:

```sh
git remote add origin https://gitea.hughboi.cc/hughboi/homelab.git
git push origin main
```

GitHub is a push mirror (auto-synced from Gitea, configured under the repo's Mirror Settings). GitHub links in docs are valid and intentional — Gitea is primary.

> [!NOTE]
> **`gitea.hughboi.cc` now resolves to dock-prod (`10.10.10.10`), not Athena.** Earlier this
> pointed straight at Athena's own IP, which broke both VPN/Tailscale clients (direct subnet
> access bypassed Traefik, hit a dead port 443) and Athena itself pulling its own public
> hostname. Pointing the record at dock-prod instead means every client — LAN, VPN, Athena
> itself, public — goes through Traefik first, which proxies to Athena over the LAN via the
> static route in `apps/docker/traefik/data/config.yml`. `http://10.10.10.8:3000/hughboi/homelab.git`
> still works as a fallback if Traefik itself is ever down.

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
