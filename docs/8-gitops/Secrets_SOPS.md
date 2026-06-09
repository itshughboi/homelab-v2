# Secrets (SOPS + Age) — Ansible & Terraform

SOPS for the **Ansible / Terraform layer** — provisioning secrets Athena needs at runtime. The
**Docker** side (`.env.sops`) is the live, fully-documented one: [sops-secrets.md](sops-secrets.md).
Kubernetes app secrets use **Sealed Secrets**, a separate tool: [index.md](index.md#secrets-in-kubernetes).

> [!IMPORTANT] Planned — not yet configured
> Today `.sops.yaml` has **only** the Docker rule (`apps/docker/**/.env.sops`) and still ships
> `AGE_PUBLIC_KEY_PLACEHOLDER` (audit **C2**). So `secrets.yaml` / `terraform.tfvars` are
> currently just **gitignored plaintext on disk**, not SOPS-encrypted-and-committed. This doc is
> the plan for wiring that up.

---

## The model (same convention as Docker)

One convention across the repo: the **plaintext** file is gitignored; its **`.sops`-encrypted**
counterpart is committed. This avoids the in-place trap (encrypting a file you also gitignore =
never committed). So:

| Plaintext (gitignored) | Encrypted (committed) |
| --- | --- |
| `ansible/.../secrets.yaml` | `ansible/.../secrets.sops.yaml` |
| `terraform/proxmox/terraform.tfvars` | `terraform/proxmox/terraform.sops.tfvars` |

What goes in them: Proxmox API token (tfvars), UniFi credentials + service API keys (secrets.yaml).

---

## Wiring it up

**1. Generate the age key on Athena** (the private key must live where Ansible/Terraform run):
```sh
./scripts/age-setup.sh     # generates ~/.config/sops/age/keys.txt, patches .sops.yaml
```

**2. Add creation-rules to `.sops.yaml`** for the encrypted file names:
```yaml
creation_rules:
  - path_regex: apps/docker/.*\.env\.sops$        # existing (Docker)
    age: "age1..."
  - path_regex: .*secrets\.sops\.yaml$            # Ansible
    age: "age1..."
  - path_regex: .*\.sops\.tfvars$                 # Terraform
    age: "age1..."
```

**3. Un-ignore the encrypted files** in `.gitignore` (plaintext stays ignored):
```gitignore
!*.sops.yaml
!*.sops.tfvars
```

**4. Encrypt and commit:**
```sh
sops --encrypt secrets.yaml > secrets.sops.yaml          # encrypt plaintext → committed copy
sops secrets.sops.yaml                                    # later: edit in place ($EDITOR, re-encrypts on save)
sops --decrypt secrets.sops.yaml                          # print plaintext to stdout
git add secrets.sops.yaml                                 # the encrypted file is safe to commit
```

Ansible/Terraform read the decrypted values at runtime via the SOPS plugin or a pre-run decrypt
step, using the Age key on Athena.

---

## Git rules

> [!DANGER]
> The **plaintext** `secrets.yaml` / `terraform.tfvars` must stay gitignored; only the
> `.sops`-encrypted copies are committed. If a plaintext secret ever lands in Git history,
> assume it's compromised — **rotate it**, even if you delete the file in the same commit.

Key backup is non-negotiable: see [sops-secrets.md → Key rotation and recovery](sops-secrets.md#key-rotation-and-recovery)
(losing the private key with no backup makes every encrypted file unreadable).
