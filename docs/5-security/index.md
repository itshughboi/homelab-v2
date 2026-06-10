# 5. Security

Security baseline configured before any production services go live. These settings apply across every VM, every container, and the k3s cluster. Do this after storage is mounted and before deploying Docker or k3s workloads.

---

## Philosophy

Security here is layered, not bolted on at the end:

- **Network layer** — VLAN segmentation isolates traffic by purpose (done in step 2)
- **Host layer** — SSH hardening, fail2ban, UFW on every Ubuntu host
- **Secrets layer** — Vaultwarden is the source of truth; SOPS+Age (provisioning files) and Sealed Secrets (k8s) are the encryption targets — both **staged but not yet active** (see [8-gitops](../8-gitops/index.md))
- **Runtime layer** — CrowdSec on k3s ingress, Wazuh SIEM across the fleet
- **CI layer** — gitleaks and Trivy scan every PR before it merges

None of these replace each other. A compromised pod that bypasses CrowdSec still hits NetworkPolicies. A leaked token still can't decrypt SOPS files without the Age key on Athena.

---

## SSH Hardening

Run immediately after bootstrapping any new host:

```sh
cd ansible/playbooks/ubuntu/hardening
ansible-playbook -i inventory.ini harden.yaml
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

Age private key lives on **Athena only**, never in Git; `.sops.yaml` (repo root) defines which
files get encrypted. The full workflow (`age-setup.sh`, encrypt/decrypt, `.sops.yaml`, Sealed
Secrets for k8s) is documented once in **[8-gitops/Secrets_SOPS.md](../8-gitops/Secrets_SOPS.md)**.

---

## Tailscale VPN

Zero-config mesh VPN for remote access without exposing ports publicly. Runs as a **subnet
router** (not an exit node) on a **dedicated VLAN-80 VM** (`vpn-gateway`, `10.10.80.254`) — *not*
on Athena. Full rationale, the `tailscale up` flags, and the required UniFi static route are in
**[Tailscale.md](Tailscale.md)**.

> Optionally, the **Tailscale Operator in k3s** (`apps/kubernetes/k3s/infra/tailscale-operator/`)
> can expose individual k8s Services on the tailnet without a Traefik IngressRoute.

---

## Wazuh (SIEM)

Wazuh currently runs as the **Docker stack on dock-prod** (`apps/docker/wazuh/`), dashboard at
`https://wazuh.hughboi.cc`, collecting events from agents on all hosts. (A k3s deployment is the
future migration target — see [Wazuh-UniFi-Logs.md](Wazuh-UniFi-Logs.md).)

Install agent on any Ubuntu host:
```sh
# Get the agent package from the Wazuh manager API or UI
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.x.x_amd64.deb
WAZUH_MANAGER="wazuh.hughboi.cc" dpkg -i wazuh-agent.deb
systemctl enable --now wazuh-agent
```

Wazuh provides:
- File integrity monitoring (detects changes to key config files)
- Log analysis and anomaly detection
- CVE vulnerability assessment per host
- Active response (can ban IPs based on rules)

→ Ingesting the UniFi gateway's syslog into Wazuh: [Wazuh-UniFi-Logs.md](Wazuh-UniFi-Logs.md)

---

## CrowdSec

CrowdSec blocks known-bad IPs. It currently runs as the Docker stack on dock-prod
(`apps/docker/crowdsec/`) with the **Traefik bouncer** (app-layer blocking at the reverse
proxy), parsing Traefik access logs and Linux/SSH auth.

> [!NOTE]
> This index also references a k3s deployment (`apps/kubernetes/k3s/networking/traefik/`)
> from the migration plan. The **live** CrowdSec is the Docker stack above — that's what the
> bouncer docs are written against.

Check ban list:
```sh
docker exec crowdsec cscli decisions list
```

→ Adding network-layer auto-block at the UniFi firewall: [CrowdSec-UniFi-Bouncer.md](CrowdSec-UniFi-Bouncer.md)

---

## Identity / SSO

Two OIDC providers, split by platform — **not** redundant:

| Provider | Serves | Where |
| --- | --- | --- |
| **Pocket ID** | Docker stack SSO (e.g. Proxmox OIDC) | dock-prod — `pocket.hughboi.cc` ([setup](../6-docker/Pocket%20ID%20-%20Proxmox.md)) |
| **Authentik** | k3s app SSO (forward-auth via Traefik) | k3s — `apps/kubernetes/k3s/apps/authentik/` |

As the Docker→k3s migration completes, Authentik becomes the primary; Pocket ID stays for
anything that remains on Docker / for Proxmox OIDC.

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

## Pod Security (securityContext + PSA)

securityContext coverage is **partial** across the k3s apps (audit **A2-M1**). The fix is a
standard baseline + a *non-breaking* rollout — not a blind mass-edit (`runAsNonRoot` /
`readOnlyRootFilesystem` break root-running or filesystem-writing apps individually).

**The container baseline** (add per deployment, in PRs — CI kubeconform-validates):

```yaml
securityContext:
  allowPrivilegeEscalation: false      # safe almost everywhere
  capabilities: { drop: ["ALL"] }      # safe almost everywhere
  seccompProfile: { type: RuntimeDefault }
  # --- add per-app once tested (these break some images): ---
  # runAsNonRoot: true
  # runAsUser: 1000                     # check the image's expected UID first
  # readOnlyRootFilesystem: true        # mount emptyDir/PVC for paths the app writes
```

**Cluster-wide guardrail without per-app edits — Pod Security Admission.** Label namespaces
(start non-blocking, then enforce as each is validated):

```yaml
# namespace.yaml labels
pod-security.kubernetes.io/enforce: baseline     # blocks privileged/hostNetwork/etc. — most apps pass
pod-security.kubernetes.io/warn: restricted      # surfaces stricter violations (non-blocking)
pod-security.kubernetes.io/audit: restricted
```

**Rollout order:** (1) add `warn/audit: restricted` everywhere → see violations harmlessly; (2)
add the safe container baseline app-by-app via PRs, starting with stateless apps; (3) move
namespaces to `enforce: baseline`; (4) pursue `restricted` per-app where feasible. **Known
exceptions:** `home-assistant` (hostNetwork) and any host-metrics pod need scoped exemptions, not
the strict profile.

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
