# 6. Security

Security baseline configured before any production services go live. These settings apply across every VM, every container, and the k3s cluster. Do this after storage is mounted and before deploying Docker or k3s workloads.

---

## Philosophy

Security here is layered, not bolted on at the end:

- **Network layer** — VLAN segmentation isolates traffic by purpose (done in step 2)
- **Host layer** — SSH hardening, fail2ban, UFW on every Ubuntu host
- **Secrets layer** — Age encryption for files at rest (SOPS), Sealed Secrets for k8s, Vaultwarden for everything else
- **Runtime layer** — CrowdSec on k3s ingress, Wazuh SIEM across the fleet
- **CI layer** — gitleaks and Trivy scan every PR before it merges

None of these replace each other. A compromised pod that bypasses CrowdSec still hits NetworkPolicies. A leaked token still can't decrypt SOPS files without the Age key on Athena.

---

## SSH Hardening

Run immediately after bootstrapping any new host:

```sh
cd ansible/playbooks/ubuntu/hardening
ansible-playbook -i inventory.ini main.yaml
```

What it enforces:
- `PasswordAuthentication no`
- `PermitRootLogin no`
- `PubkeyAuthentication yes`
- Max auth tries, login grace time, idle disconnect

Verify after running:
```sh
cd ansible/playbooks/ubuntu/check-ssh-config
ansible-playbook -i <inventory> main.yaml
```

---

## Host Hardening (UFW + fail2ban)

Applied by `new-host-bootstrap` and the `hardening` playbook:

```sh
cd ansible/playbooks/ubuntu/new-host-bootstrap
ansible-playbook -i inventory.yaml main.yaml
```

- UFW: deny all inbound, allow outbound, explicit allow for SSH (+ service ports per host)
- fail2ban: SSH jail active on all hosts, bans after 3 failed attempts
- unattended-upgrades: security patches apply automatically

Check fail2ban activity:
```sh
cd ansible/playbooks/ubuntu/fail2ban-report
ansible-playbook -i <inventory> main.yaml
```

---

## SOPS / Age (Secrets at Rest)

Age key lives on Athena only. Never in Git.

```sh
# Initial setup — run once on Athena
./scripts/age-setup.sh

# Encrypt a file
sops --encrypt --age $(cat ~/.config/sops/age/keys.txt | grep public | awk '{print $4}') \
  secret.yaml > secret.enc.yaml

# Decrypt
sops --decrypt secret.enc.yaml
```

`.sops.yaml` in the repo root defines which files get encrypted and which Age public key to use. The private key never leaves Athena.

→ Full GitOps workflow and Sealed Secrets integration: [9-gitops/Secrets_SOPS.md](../9-gitops/Secrets_SOPS.md)

---

## Tailscale VPN

Tailscale provides zero-config mesh VPN — used for remote access to internal services without exposing ports publicly.

**Install on a host:**
```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<tskey-from-vaultwarden>
```

**Tailscale Operator in k3s** (`apps/kubernetes/k3s/infra/tailscale-operator/`) — exposes k8s Services directly on the Tailnet. No Traefik IngressRoute needed for internal-only services.

**Key devices:**
- Athena (10.10.10.8) — always-on exit node for remote admin
- Your Mac — primary client

---

## Wazuh (SIEM)

Wazuh runs in k3s (`apps/kubernetes/k3s/apps/wazuh/`) and collects security events from agents installed on all hosts.

Install agent on any Ubuntu host:
```sh
# Get the agent package from the Wazuh manager API or UI
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.x.x_amd64.deb
WAZUH_MANAGER="wazuh.hughboi.vip" dpkg -i wazuh-agent.deb
systemctl enable --now wazuh-agent
```

Wazuh provides:
- File integrity monitoring (detects changes to key config files)
- Log analysis and anomaly detection
- CVE vulnerability assessment per host
- Active response (can ban IPs based on rules)

---

## CrowdSec (k3s Ingress)

CrowdSec runs as a Traefik bouncer in k3s, blocking known bad IPs at the ingress layer. Configuration in `apps/kubernetes/k3s/networking/traefik/`.

Metrics flow to Prometheus automatically (scrape job in `kube-prometheus-stack/values.yaml`).

Check ban list:
```sh
kubectl exec -n crowdsec deploy/crowdsec -- cscli decisions list
```

---

## Kubernetes NetworkPolicies

Default-deny is applied to all app namespaces. Explicit allow rules for:
- DNS egress (all pods need DNS)
- Traefik ingress (pods with IngressRoutes)
- Prometheus scraping (monitoring namespace → all namespaces)

Apply to a new namespace:
```sh
kubectl apply -f apps/kubernetes/k3s/networking/network-policies/default-deny.yaml -n <namespace>
kubectl apply -f apps/kubernetes/k3s/networking/network-policies/allow-dns.yaml -n <namespace>
kubectl apply -f apps/kubernetes/k3s/networking/network-policies/allow-traefik-ingress.yaml -n <namespace>
kubectl apply -f apps/kubernetes/k3s/networking/network-policies/allow-monitoring-scrape.yaml -n <namespace>
```

Apps that need cross-namespace communication get their own `networkpolicy.yaml` (see `authentik/`, `gitea/`, `vaultwarden/`).

---

## CI Security Scanning

Every PR runs two security scans automatically (`.gitea/workflows/ci.yaml`):

**gitleaks** — scans the full git history for accidentally committed secrets (API keys, passwords, tokens):
```sh
gitleaks detect --source . --log-level warn
```

**Trivy** — scans k8s manifests for misconfigurations and Dockerfiles for known CVEs:
```sh
trivy config --severity HIGH,CRITICAL apps/kubernetes/
```

Both run on every push to non-main branches and every PR to main. A failed scan blocks the merge.

---

## Routine Security Checks (Semaphore schedule)

| Playbook | Frequency | Purpose |
|---|---|---|
| `ubuntu/check-ssh-config` | Monthly | Verify SSH hardening hasn't drifted |
| `ubuntu/audit-users` | Monthly | Sudo users, passwordless accounts, authorized_keys |
| `ubuntu/audit-listening-ports` | Monthly | Catch unexpected exposed ports |
| `ubuntu/lynis-scan` | Quarterly | Full CIS-style hardening audit, score ≥ 65 |
| `ubuntu/disk-health` | Weekly | SMART status on all drives |
| `ubuntu/fail2ban-report` | Weekly | Current bans and top attacking IPs |
| `ubuntu/ssl-cert-expiry` | Daily | Alert before any cert expires |

→ All playbooks at `ansible/playbooks/ubuntu/`
