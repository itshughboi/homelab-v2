---
title: "9. GitOps"
weight: 90
bookCollapseSection: true
---

# 9. GitOps

ArgoCD + Sealed Secrets + SOPS/Age. Push to Git → cluster applies it. App secrets encrypted in Git via Sealed Secrets (decrypted in-cluster). Ansible/Terraform secrets encrypted via SOPS+Age (decrypted on Athena). Every deployment is a `git push`.

---

## How It Works

```
Developer pushes to Gitea
    → ArgoCD polls Gitea every 3 minutes (or via webhook immediately)
    → ArgoCD diffs current cluster state vs Git
    → ArgoCD applies what's changed
    → Cluster is now in sync with Git

Kubernetes app secrets (Sealed Secrets):
    → kubectl create secret --dry-run | kubeseal → sealed-secret.yaml
    → Commit encrypted file to Gitea (safe)
    → ArgoCD applies SealedSecret → in-cluster controller decrypts → Secret exists

Ansible/Terraform secrets (SOPS + Age):
    → sops --encrypt secrets.yaml / terraform.tfvars
    → Encrypted file pushed to Gitea (safe)
    → At runtime: Athena decrypts using Age private key (never leaves Athena)
```

---

## ArgoCD

See [`8-k3s/index.md#gitops`](../8-k3s/index.md#gitops-argocd) for the full install sequence.

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

Full reference: [`Secrets_SOPS.md`](Secrets_SOPS.md)

### Setup (One-Time, on Athena)

```sh
apt install age sops

# Generate keypair — private key NEVER leaves Athena
age-keygen -o ~/.config/sops/age/keys.txt
# Save the public key output: age1...

# Auto-populate .sops.yaml in repo:
./scripts/age-setup.sh
```

### .sops.yaml

```yaml
creation_rules:
  - path_regex: secrets\.yaml$
    age: "age1..."
  - path_regex: terraform\.tfvars$
    age: "age1..."
```

This file is safe to commit — it contains only the public key.

### Encrypt / Decrypt

```sh
sops --encrypt --in-place secrets.yaml   # encrypt in place
sops secrets.yaml                         # open decrypted in $EDITOR (re-encrypts on save)
sops --decrypt secrets.yaml               # print decrypted to stdout
```

### What Gets Encrypted

| File | Contains |
| --- | --- |
| `terraform/proxmox/terraform.tfvars` | Proxmox API token |
| `ansible/playbooks/*/secrets.yaml` | UniFi credentials, service API keys |
| Any file with passwords, tokens, API keys before committing |

---

## Git Rules (Non-Negotiable)

```gitignore
# Terraform secrets — never commit
terraform.tfvars
terraform.tfvars.json
*.tfstate
*.tfstate.backup
.terraform/

# Application secrets
secrets.yaml
.env
*.key
proxmox.pkrvars.sh
```

> [!DANGER]
> **If a plaintext secret touches Git history, assume it is compromised.**
> Rotation is mandatory — not optional — even if you delete the file in the same commit.
> Check the commit SHA is not cached anywhere before considering a secret safe.

---

## Secrets in Kubernetes

Two approaches used in this cluster:

### 1. Imperative (Preferred for Sensitive Values)

Create secrets directly via `kubectl`. They never appear in any file in Git.

```sh
kubectl create secret generic my-app-secret \
  -n my-app \
  --from-literal=api-key=<value> \
  --from-literal=db-password=<value>
```

Each app that needs secrets has a `secret.yaml` in its app directory containing only comments explaining what to create:

```yaml
# Create this secret imperatively before ArgoCD syncs this app:
# kubectl create secret generic my-app-secret \
#   -n my-app \
#   --from-literal=api-key=<value>
#
# Get the value from Vaultwarden: homelab / my-app / api-key
```

### 2. Sealed Secrets (For Git-Safe Encrypted Secrets)

Sealed Secrets encrypts a Kubernetes Secret so it can be committed to Git. Only the sealed-secrets controller in the cluster can decrypt it.

```sh
# Encrypt a secret for Git
kubectl create secret generic my-secret --dry-run=client \
  --from-literal=key=value -o yaml | \
  kubeseal --format yaml > my-secret-sealed.yaml

# Commit and push — ArgoCD applies the SealedSecret, controller decrypts it
git add my-secret-sealed.yaml && git commit && git push
```

> [!DANGER]
> Backup the Sealed Secrets controller key. Without it, encrypted secrets are unrecoverable.
> ```sh
> kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
>   -o yaml > sealed-secrets-key-backup.yaml
> # Store in Vaultwarden — NEVER commit to git
> ```

---

## GitHub Mirror

Gitea is primary. GitHub is a read-only push mirror configured in Gitea:
- Gitea → Repository Settings → Mirror → Push Mirror → GitHub URL

GitHub links in this repo's docs are valid and intentional. Push to Gitea, GitHub syncs automatically.

---

## Secret Rotation Checklist (Annual)

- [ ] Proxmox API token (`terraform@pve`) — update in `terraform.tfvars` + re-encrypt
- [ ] Packer API token (`packer@pve`)
- [ ] UniFi local admin password — used by Ansible playbooks
- [ ] TSIG key (Bind9 / Terraform DNS) — regenerate + re-encrypt
- [ ] Age keypair — generate new key, re-encrypt all SOPS files, update `.sops.yaml`
- [ ] Tailscale auth keys — rekey all devices
- [ ] PBS datastore credentials
- [ ] Sealed Secrets controller key backup — verify copy is still in Vaultwarden
- [ ] Cloudflare API token (cert-manager / Traefik)

Use a Semaphore scheduled task or Gitea issue as an annual reminder.
