# Security Audit — May 2026

Conducted after initial infrastructure build-out. Findings rated by impact and likelihood.
Items marked ✅ are fixed in this repo. Items marked 📋 require manual action (UI, secrets, live hosts).

---

## Summary

### Audit 1 (initial)
| Severity | Count | Fixed in code | Manual required |
|----------|-------|--------------|-----------------|
| Critical | 3 | 2 | 1 |
| High | 4 | 2 | 2 |
| Medium | 4 | 1 | 3 |
| Low | 2 | 0 | 2 |

### Audit 2 (follow-up — network + deeper k3s review)
| Severity | Count | Fixed in code | Manual required |
|----------|-------|--------------|-----------------|
| High | 1 | 0 | 1 |
| Medium | 3 | 1 | 2 |
| Network | 3 | 2 | 1 |

---

## Critical

### C1 — Prometheus exposed publicly with no authentication ✅ Fixed
**Risk:** `prometheus.hughboi.vip` was reachable by anyone. Prometheus has no built-in auth.
An attacker could read every scrape target, internal IP address, alert rule, and service name —
a complete map of the homelab without needing to scan anything.

**Fix applied:** Added an IP-allowlist Traefik middleware to the IngressRoute. Prometheus is now
only reachable from RFC-1918 addresses (10.0.0.0/8, 192.168.0.0/16, 172.16.0.0/12) and
Tailscale's CGNAT range (100.64.0.0/10). Public internet gets a 403.

**File:** `apps/kubernetes/k3s/monitoring/kube-prometheus-stack/prometheus-ingressroute.yaml`

---

### C2 — SOPS not actually configured (placeholder not replaced) 📋 Manual
**Risk:** `.sops.yaml` contains `AGE_PUBLIC_KEY_PLACEHOLDER`. SOPS encryption is **not active**.
Any `.env.sops` file created believing it is encrypted is actually stored in plaintext.

**Why this matters:** SOPS is the entire secrets-at-rest strategy. Without the age key configured,
there is no encryption — secrets would be committed to Git in cleartext.

**Fix (manual — must run on Athena):**
```sh
# On Athena
./scripts/age-setup.sh
# This generates an age keypair, stores the private key in ~/.config/sops/age/keys.txt,
# and outputs the public key to paste into .sops.yaml
```
Then commit the updated `.sops.yaml` (the PUBLIC key is safe to commit — the private key never leaves Athena).

**Verify:** `sops --version` and `cat .sops.yaml | grep age:` — should show a real age public key, not the placeholder.

---

### C3 — Gitea CI runner has unrestricted Docker socket access 📋 Manual
**Risk:** `apps/docker/gitea/compose.yaml` mounts `/var/run/docker.sock` into the runner container.
Any CI job can run:
```sh
docker run --privileged -v /:/host alpine chroot /host bash
```
This gives the job full root on dock-prod. A malicious PR, a compromised Gitea account, or a
supply-chain attack on an action used in CI is all it takes.

**Why this is hard to fix:** The Docker socket is needed to build and run Docker images in CI.
True alternatives require replacing Docker-in-Docker (DinD) or rootless Podman.

**Mitigations (in priority order):**

1. **Restrict which repos trigger the runner** — In Gitea admin: Settings → Actions → Runners.
   Set the runner to only accept jobs from this specific repo, not all repos.

2. **Require PR approval before CI runs** — In Gitea repo: Settings → Branches → Branch protection
   on `main`. Enable "Require approval before running actions for first-time contributors."
   This prevents a fork PR from running CI without a maintainer review.

3. **Use Gitea's built-in allowlist** — In `.gitea/workflows/ci.yaml`, add:
   ```yaml
   on:
     push:
       branches: [main]
     pull_request:
       types: [opened, synchronize]
   ```
   This limits CI triggers. Never use `pull_request_target` unless you know exactly what it does.

4. **Long-term:** Migrate to rootless Podman or kaniko for image builds, eliminating docker.sock.

---

## High

### H1 — ArgoCD self-heals from Gitea without branch protection ✅ Partial fix (see H2)
**Risk:** ArgoCD has `selfHeal: true` and `prune: true`. If an attacker pushes to `main`,
ArgoCD deploys it within 3 minutes — no manual approval, no review gate.

**Fix:** Branch protection on `main` (see H2) eliminates push-to-main. But the real defense is
that ArgoCD's Gitea credentials should have read-only access to the repo, not write access.
ArgoCD only needs to pull — verify the repo token scopes.

---

### H2 — No 2FA on Gitea admin account and no branch protection on main 📋 Manual
**Risk:** A single compromised password = full cluster control via ArgoCD.

**Fix (manual — Gitea UI):**

**Enable TOTP on your admin account:**
1. Gitea → User Settings → Security → Two-Factor Authentication → Enroll
2. Scan QR with Authenticator app (Aegis recommended)
3. Save backup codes in Vaultwarden

**Enable branch protection on main:**
1. Repo → Settings → Branches → Add Rule
2. Branch name pattern: `main`
3. Enable: "Require pull request reviews before merging" (min 1 approval)
4. Enable: "Block force push"
5. Enable: "Require status checks to pass" → select your CI checks

**What this achieves:** Even your own admin account can't push directly to main.
All changes go through PRs. ArgoCD's access is read-only pull.

---

### H3 — Cloudflare API token in cert-manager can take over your entire DNS 📋 Manual
**Risk:** The Cloudflare token stored as a k8s secret in `cert-manager` has DNS-edit permissions
for all zones. If the cluster is compromised and an attacker reads secrets, they can:
- Create DNS records pointing your domains at their servers
- Issue their own TLS certificates for your domains
- Intercept all traffic to `*.hughboi.cc` and `*.hughboi.vip`

**Fix (manual):**
1. In Cloudflare dashboard → My Profile → API Tokens → Edit your cert-manager token
2. Change "Zone permissions" from `Zone:Edit` to only `DNS:Edit`
3. Restrict the token to only the specific zones (`hughboi.cc`, `hughboi.vip`) — not all zones
4. Set an IP filter on the token to only allow requests from your k3s node IPs
5. Rotate the token and update the k8s secret:
   ```sh
   kubectl delete secret cloudflare-token -n cert-manager
   kubectl create secret generic cloudflare-token -n cert-manager \
     --from-literal=api-token=<new-restricted-token>
   ```

---

### H4 — Vaultwarden publicly accessible, holds keys to everything 📋 Manual
**Risk:** `vault.hughboi.vip` is internet-accessible. Vaultwarden holds Sealed Secrets backup key,
Proxmox API tokens, SSH keys, and all credentials. A Vaultwarden vulnerability or weak master
password means an attacker gets everything at once.

**Fixes:**
1. Put Vaultwarden behind Authentik SSO forward-auth (Authentik is already in the stack)
2. Enable Vaultwarden admin token and restrict admin page to internal IPs only
3. Enable Fail2ban in Vaultwarden config (`/admin` and `/api/accounts/prelogin` are brute-forceable)
4. Store the Sealed Secrets private key backup in a second location (encrypted USB, paper)
   — if Vaultwarden is down during a cluster rebuild, you're locked out of sealed secrets
5. Set `SIGNUPS_ALLOWED=false` in Vaultwarden env — no new account registrations

---

## Medium

### M1 — No egress NetworkPolicies — compromised pods can phone home ✅ Fixed
**Risk:** Default-deny only blocks inbound traffic. A compromised pod can make outbound connections
to C2 servers, exfiltrate data, or reach other internal services by IP.

**Fix applied:** Added `default-deny-egress.yaml`, `allow-dns-egress.yaml`, and
`allow-https-egress.yaml` to `apps/kubernetes/k3s/networking/network-policies/`.

**Important:** Egress policies are more disruptive than ingress ones. Test on one namespace first
before applying fleet-wide. Some apps need internet access (image pulls, external APIs) —
add explicit allow rules for those.

---

### M2 — Proxmox API tokens have Administrator role (too broad) 📋 Manual
**Risk:** `terraform@pve` and `packer@pve` have Administrator privileges. If tokens leak,
an attacker has full Proxmox API access — create/delete VMs, access consoles, reset passwords.

**Fix (manual — Proxmox UI):**

What each token actually needs:

**Terraform token** (`terraform@pve`):
- VM.Allocate, VM.Clone, VM.Config.*, VM.Monitor, VM.PowerMgmt on `/`
- Datastore.AllocateSpace on storage pools
- Pool.Audit on `/pool`

**Packer token** (`packer@pve`):
- Same as Terraform (builds VMs and converts to templates)

Steps:
1. Proxmox UI → Datacenter → Permissions → Roles → Create role `terraform-role`
2. Add only the permissions listed above
3. Datacenter → Permissions → Users → `terraform@pve` → set role to `terraform-role`
4. Revoke `Administrator` role
5. Regenerate the token (`pveum user token add terraform@pve terraform --privsep=0`)
6. Update `terraform.tfvars` with new token

---

### M3 — Wazuh SIEM on same host as production services 📋 Long-term
**Risk:** Wazuh runs on dock-prod alongside production Docker containers.
A sophisticated attacker who compromises dock-prod can neutralize the SIEM before triggering alerts,
preventing detection of the intrusion itself.

**Ideal fix:** Move Wazuh to a dedicated management VM on Athena's VLAN,
reachable only from the management network.

**Acceptable near-term:** Ensure dock-prod's UFW only allows Wazuh agent traffic (port 1514/1515)
from internal IPs. No public exposure of Wazuh.

---

### M4 — Multiple Docker containers mount docker.sock unnecessarily 📋 Manual
**Risk:** Beyond the Gitea runner, several containers on dock-prod mount the Docker socket.
Each is a potential container escape. Audit which ones actually need it:

| Container | Needs docker.sock? | Alternative |
|-----------|-------------------|-------------|
| Gitea runner | Yes (CI builds) | kaniko / Podman |
| Traefik | Yes (service discovery) | Static config (but loses auto-discovery) |
| Homepage | Yes (container status widget) | Remove widget or use API |
| Portainer | Yes (management UI) | Accept risk or remove Portainer |
| Promtail | Yes (Docker log collection) | Alloy (already configured) |
| Telegraf | Yes (Docker metrics) | cAdvisor (separate) |
| Glances | No | Use Glances in API mode with pre-configured targets |
| Diun | Yes (image update notifications) | Accept risk or use Renovate only |

---

## Low

### L1 — Longhorn replication traffic is unencrypted 📋 Low priority
**Risk:** Replica sync between Longhorn nodes on VLAN 40 is not encrypted.
An attacker with access to VLAN 40 could read data in transit.

**Context:** VLAN 40 is the dedicated storage VLAN with no workload traffic.
Only Longhorn nodes and workers with explicit VLAN 40 access can see this traffic.
Acceptable risk for a homelab — document if compliance becomes a requirement.

**Fix (if needed):** Enable WireGuard in Longhorn settings (`Settings → General → Use WireGuard Encryption`).
Adds CPU overhead.

---

### L2 — Shared SSH key across all VMs (no rotation schedule) 📋 Low priority
**Risk:** One compromised key = all 12 VMs accessible simultaneously.
No key rotation means a stolen key stays valid indefinitely.

**Fix:**
1. Generate a second ed25519 key for a specific new purpose (admin vs. automation)
2. Use the `audit-users` playbook monthly — it checks authorized_keys on all hosts
3. Set a calendar reminder to rotate the `homelab-datacenter` key annually

---

## What's Working Well

These controls are correctly implemented and should be maintained:

- ✅ VLAN segmentation (management / k3s / storage / torrent / IoT)
- ✅ SSH hardening: no passwords, no root login, idle disconnect
- ✅ fail2ban: 3 attempts = ban, across all hosts
- ✅ UFW default-deny inbound on all hosts
- ✅ CrowdSec on k3s ingress (blocks known-bad IPs before they hit Traefik)
- ✅ gitleaks in CI (scans git history for accidentally committed secrets)
- ✅ unattended-upgrades (security patches apply automatically)
- ✅ NetworkPolicies (ingress default-deny on all app namespaces)
- ✅ TLS everywhere via cert-manager + Let's Encrypt wildcard
- ✅ Trivy in CI (k8s manifest misconfig scanning)
- ✅ Sealed Secrets (encrypted secrets safe to commit — when configured)
- ✅ Tailscale for remote admin (no open ports to the internet for SSH)

---

---

## Audit 2 — Follow-up Findings

### A2-H1 — Traefik has `insecureSkipVerify=true` globally 📋 Manual
**Risk:** `apps/kubernetes/k3s/networking/traefik/helm/traefik/values.yaml` sets
`--serversTransport.insecureSkipVerify=true`. This disables TLS verification for all
backend services — Traefik will accept any certificate from any backend, including expired,
self-signed, or attacker-controlled ones. A man-in-the-middle between Traefik and a backend
pod would go undetected.

**Why it's set:** Backend pods use self-signed certs or no TLS at all, which is common.
The fix is not to remove it blindly — that would break services — but to replace it with
per-service trust using a `ServersTransport` CRD.

**Fix:**
```yaml
# Create a ServersTransport that only skips verification for specific services
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: skip-verify
  namespace: traefik
spec:
  insecureSkipVerify: true
```
Then reference `serversTransport: skip-verify` only on IngressRoutes that actually need it,
and remove the global flag from `values.yaml`. Long-term: provision an internal CA with
cert-manager and issue certificates to backend services.

---

### A2-M1 — 16 k3s deployments run as root (no securityContext) 📋 Manual
**Risk:** Pods with no `securityContext` run as UID 0 (root) inside the container. A
container vulnerability gives the attacker root inside the container, making filesystem
writes, binary injection, and privilege escalation easier.

**Affected deployments:** `pocket-id`, `homepage`, `ntfy`, `freshrss`, `fasten-health`,
`n8n`, `gitea`, `semaphore`, `home-assistant`, `romm`, `mealie`, `gatus`, `hoarder`,
`ezbookkeeping`, `netbootxyz`, `prometheus-pve-exporter`.

**Fix — add to each deployment's container spec:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000          # check the image's expected UID first
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```
Note: `home-assistant` uses `hostNetwork: true` and may need specific UIDs/caps. Test
individually. `readOnlyRootFilesystem` will break apps that write to their container
filesystem — mount an `emptyDir` or PVC for those paths.

---

### A2-M2 — DHCP enabled on Storage VLAN 40 and Cluster VLAN 20 ✅ Documented
**Risk:** A rogue or misconfigured device on VLAN 40 could receive an IP and access
NFS/PBS/iSCSI. VLAN 20 has no legitimate DHCP clients — Corosync is configured at
the host level with static IPs.

**Fix (manual — UniFi UI):**
- Networks → VLAN 20 → DHCP Mode → **None**
- Networks → VLAN 40 → DHCP Mode → **None**

Both are now documented as disabled in the VLAN table.

---

### A2-N1 — k3s VLAN 30 DHCP pool overlaps static node IPs ✅ Documented
**Risk:** Old DHCP pool (`.1–.20`) directly overlaps k3s master IPs (.1–.3), worker IPs
(.11–.13), and kube-vip (.30). An IP conflict at the wrong moment can silently partition
a control plane node — the hardest failure mode to diagnose.

**Fix (manual — UniFi UI):**
- Networks → VLAN 30 → DHCP → Start: `10.10.30.200`, End: `10.10.30.220`

Updated in docs. Apply immediately.

---

### A2-N2 — No IoT VLAN ✅ Documented + NetworkPolicy added
**Risk:** Smart home devices connected to Home Assistant have no network isolation.
A compromised bulb or lock can reach management infrastructure directly.

**Fix applied:**
- VLAN 50 (IoT, `10.10.50.0/24`) added to all networking docs
- Firewall rules documented in `Unifi/Firewall/Rules.md`
- Home Assistant `networkpolicy.yaml` created with explicit IoT egress allow
- IoT WiFi SSID guidance added

**Manual steps remaining:**
1. Create VLAN 50 in UniFi → Networks → Create New Network
2. Create IoT SSID → WiFi → Create → bind to VLAN 50
3. Add firewall rules per `Unifi/Firewall/Rules.md` → IoT section
4. Enable mDNS forwarding between VLAN 30 and VLAN 50 in UniFi
5. Move smart home devices to the IoT SSID / VLAN 50

---

### A2-N3 — Longhorn metrics port missing from MONITOR firewall service group 📋 Manual
**Risk:** The `MONITOR` service group in UniFi covers ports `9100, 9090, 3000, 3100, 8086`.
Longhorn manager exposes metrics on port `9500`. Prometheus scrapes this from the monitoring
namespace across the VLAN boundary — if the firewall silently drops it, Longhorn metrics
disappear from Grafana without an obvious error.

**Fix (manual — UniFi UI):**
- Networking → Firewall & Security → Port/IP Groups → MONITOR → add port `9500`

---

## Remediation Checklist

### Can do right now (< 30 min each)
- [ ] Run `./scripts/age-setup.sh` on Athena, commit updated `.sops.yaml`
- [ ] Enable TOTP on Gitea admin account
- [ ] Enable branch protection on `main` in Gitea
- [ ] Set `SIGNUPS_ALLOWED=false` in Vaultwarden env
- [ ] Restrict Gitea runner to only this repo in Gitea admin UI
- [ ] Fix VLAN 30 DHCP pool → `10.10.30.200–220` in UniFi
- [ ] Disable DHCP on VLAN 20 and VLAN 40 in UniFi
- [ ] Add port 9500 to MONITOR service group in UniFi

### This week
- [ ] Create IoT VLAN 50 in UniFi + IoT WiFi SSID
- [ ] Add IoT firewall rules per `docs/1-networking/Unifi/Firewall/Rules.md`
- [ ] Scope Proxmox API tokens to minimum permissions (create `terraform-role`)
- [ ] Rotate Cloudflare API token with restricted zone-only DNS permissions
- [ ] Add Vaultwarden admin behind IP restriction

### This month
- [ ] Move Wazuh to Athena or dedicated management VM
- [ ] Evaluate kaniko/Podman to remove docker.sock from Gitea runner
- [ ] Apply egress NetworkPolicies to one namespace, then fleet-wide
- [ ] Add `securityContext` to the 16 deployments running as root
- [ ] Replace global `insecureSkipVerify` in Traefik with per-service ServersTransport
