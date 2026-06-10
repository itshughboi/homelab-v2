# 8. GitOps

ArgoCD + SOPS/Age. Push to Git → cluster applies it. Secrets encrypted at rest, decrypted at runtime on Athena. Every app deployment is a `git push`.

> [!TIP] Making a change? See **[Workflow.md](Workflow.md)** — the branch → PR → merge → deploy
> flow, what gets validated where (CI vs runtime), and how to roll back with `git revert`.

---

## How It Works

```
Developer pushes to Gitea
    → ArgoCD polls Gitea every 3 minutes (or via webhook immediately)
    → ArgoCD diffs current cluster state vs Git
    → ArgoCD applies what's changed
    → Cluster is now in sync with Git

Secrets:
    → SOPS encrypts values in-place before commit
    → Encrypted file pushed to Gitea (safe)
    → At runtime: SOPS decrypts using Age key stored only on Athena
```

---

## ArgoCD

See [`7-k3s/index.md#gitops`](../7-k3s/index.md#gitops-argocd) for the full install sequence.

### App of Apps Pattern

The root Application (`apps/root-app.yaml`) watches `apps/kubernetes/k3s/apps/` and creates a child Application for every subdirectory it finds. Adding a new app = add a directory + push. No manual ArgoCD configuration needed.

```
apps/root-app.yaml
    → apps/kubernetes/k3s/apps/traefik/     → ArgoCD Application: traefik
    → apps/kubernetes/k3s/apps/grafana/     → ArgoCD Application: grafana
    → apps/kubernetes/k3s/apps/vaultwarden/ → ArgoCD Application: vaultwarden
    → apps/kubernetes/k3s/apps/<new-app>/   → ArgoCD Application: new-app (auto)
```

### Connecting ArgoCD to Gitea

```sh
argocd login argocd.hughboi.vip

# Register Gitea over HTTPS (preferred over SSH for webhooks)
argocd repo add https://gitea.hughboi.cc/hughboi/homelab.git \
  --username hughboi \
  --password <gitea-personal-access-token>
```

Internal k3s DNS alternative (avoids external Gitea dependency):
```
http://gitea.gitea.svc.cluster.local:3000/hughboi/homelab.git
```

### Webhook (Instant Sync)

Instead of waiting for ArgoCD's 3-minute poll, configure a Gitea webhook for instant sync:
- Gitea → Repository Settings → Webhooks → Add Webhook
- URL: `https://argocd.hughboi.vip/api/webhook`
- Events: Push events

### Useful ArgoCD Commands

```sh
# Check all application statuses
kubectl get applications -n argocd

# Force sync a specific app
argocd app sync <app-name>

# See what ArgoCD would change (dry run)
argocd app diff <app-name>

# Roll back an app to previous version
argocd app rollback <app-name> <revision>

# Get initial admin password (only after first install)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## SOPS + Age

One SOPS convention across the repo: **plaintext files are gitignored; their `.sops`-encrypted
counterparts are committed** (the encrypted form is safe — age/AES-256-GCM). Two scopes, two
docs:

| Scope | Files | Status | Doc |
| --- | --- | --- | --- |
| **Docker** | `apps/docker/**/.env` → `.env.sops` | Rule present; **inactive** (placeholder key) | [sops-secrets.md](sops-secrets.md) |
| **Ansible / Terraform** | `secrets.yaml`, `terraform.tfvars` → `.sops` versions | Rules present; **inactive** (placeholder key) | [Secrets_SOPS.md](Secrets_SOPS.md) |

> [!IMPORTANT] Not active until the age key is set
> `.sops.yaml` still ships `AGE_PUBLIC_KEY_PLACEHOLDER` — SOPS encrypts nothing until you run
> `./scripts/age-setup.sh` on Athena (audit finding **C2**). Until then, secrets like
> `terraform.tfvars` are just gitignored plaintext on disk, **not** encrypted-and-committed.

Setup, encrypt/decrypt, multi-machine, rotation, and recovery are documented in the two scope
docs above — not duplicated here.

---

## Git Rules (Non-Negotiable)

```gitignore
# Plaintext secrets — never commit
terraform.tfvars
terraform.tfvars.json
*.tfstate
*.tfstate.backup
.terraform/
secrets.yaml
.env
*.key
proxmox.pkrvars.sh

# SOPS-encrypted counterparts ARE safe to commit — un-ignore them
!*.env.sops
```

> The rule: the **plaintext** name is gitignored; the **`.sops`-encrypted** name is committed
> (encrypted values are safe). This is why `.env` is ignored but `.env.sops` is un-ignored.
> When the Ansible/TF path is wired up, its encrypted files get un-ignored the same way.

> [!DANGER]
> **If a plaintext secret touches Git history, assume it is compromised.**
> Rotation is mandatory — not optional — even if you delete the file in the same commit.
> Check the commit SHA is not cached anywhere before considering a secret safe.

---

## Secrets in Kubernetes

Two tools handle secrets, operating at different layers — not alternatives to each other:

| Tool | Layer | What it encrypts | Who decrypts |
|------|-------|------------------|--------------|
| **Sealed Secrets** | Kubernetes / ArgoCD | k8s `Secret` objects | In-cluster controller |
| SOPS + Age | Ansible / Terraform | `.tfvars`, `secrets.yaml` for provisioning | Athena at runtime |

> [!IMPORTANT] Current reality: apps use **imperative** secrets, not Sealed Secrets (yet)
> The Sealed Secrets controller is installed (`infra/sealed-secrets/`), but **no app uses it
> yet** — every app ships a comment-only `secret.yaml` that you must `kubectl create` by hand
> before ArgoCD syncs it (the "Imperative Secrets" pattern below). **Migrating apps to Sealed
> Secrets is the target** — until then, those secrets live only in Vaultwarden, not Git, which
> is a DR gap (a rebuild requires re-entering them). Treat §1 below as the goal and §2 as
> what's live today.

### 1. Sealed Secrets (target — automated, GitOps-native; not yet adopted)

Sealed Secrets encrypts a Kubernetes Secret so it can be safely committed to Git. The sealed-secrets controller running in-cluster holds the private key and decrypts `SealedSecret` objects back into real `Secret` objects automatically. ArgoCD treats them like any other manifest.

**Install the controller once during bootstrap** (before ArgoCD first syncs — see `infra/sealed-secrets/`):

```sh
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  -f apps/kubernetes/k3s/infra/sealed-secrets/values.yaml
```

**Install kubeseal CLI** (on the machine you seal from — laptop or Athena):
```sh
brew install kubeseal   # macOS
# or: download binary from https://github.com/bitnami-labs/sealed-secrets/releases
```

**Create and commit a sealed secret:**
```sh
# 1. Generate the secret as a dry-run (never apply this directly)
kubectl create secret generic my-app-secret -n my-app \
  --from-literal=api-key=<value> \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml

# 2. Commit it — it's encrypted, safe to push
git add apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml && git commit && git push

# ArgoCD applies the SealedSecret → controller decrypts → Secret appears in namespace
```

> [!DANGER]
> **Back up the controller key immediately after install.** If you rebuild the cluster and lose this key, all sealed secrets are permanently unreadable.
> ```sh
> kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
>   -o yaml > ~/sealed-secrets-master.key
> # Store in Vaultwarden — NEVER commit to git
> ```

### 2. Imperative Secrets (Reference / Break-Glass)

Use this when the sealed-secrets controller isn't running yet (early bootstrap stages) or for emergency one-off access.

```sh
kubectl create secret generic my-app-secret \
  -n my-app \
  --from-literal=api-key=<value> \
  --from-literal=db-password=<value>
```

Each app that uses imperative secrets has a `secret.yaml` in its app directory containing only comments — no plaintext values:

```yaml
# Create this secret imperatively before ArgoCD syncs this app:
# kubectl create secret generic my-app-secret \
#   -n my-app \
#   --from-literal=api-key=<value>
#
# Get the value from Vaultwarden: homelab / my-app / api-key
```

ArgoCD ignores existing Secrets (via `ignoreDifferences` on `/data`) so it won't overwrite or delete imperatively-created secrets.

---

## GitHub Mirror

Gitea is primary. GitHub is a read-only push mirror configured in Gitea:
- Gitea → Repository Settings → Mirror → Push Mirror → GitHub URL

GitHub links in this repo's docs are valid and intentional. Push to Gitea, GitHub syncs automatically.

---

## Secret Rotation Checklist (Annual)

**Sealed Secrets:**
- [ ] Verify controller key backup is still in Vaultwarden (`sealed-secrets-master.key`)
- [ ] `kubeseal --re-encrypt` any secrets if key rotation is needed

**SOPS / Terraform / Ansible:**
- [ ] Proxmox API token (`terraform@pve`) — update in `terraform.tfvars` + re-encrypt
- [ ] Packer API token (`packer@pve`)
- [ ] UniFi local admin password — used by Ansible playbooks
- [ ] TSIG key (Bind9 / Terraform DNS) — regenerate + re-encrypt
- [ ] Age keypair — generate new key, re-encrypt all SOPS files, update `.sops.yaml`

**Network / Infrastructure:**
- [ ] Tailscale auth keys — rekey all devices
- [ ] PBS datastore credentials
- [ ] Cloudflare API token (cert-manager / Traefik)

Use a Semaphore scheduled task or Gitea issue as an annual reminder.
