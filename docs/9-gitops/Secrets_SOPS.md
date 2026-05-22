# Secrets Management (SOPS + Age)

Since everything is in Git, passwords and API keys cannot be stored in plain text.

---

## The Approach: Mozilla SOPS + Age

**SOPS** (Secrets OPerationS) encrypts individual values inside a file while keeping
the structure readable. **Age** is the encryption backend — simple, modern, no GPG complexity.

**The workflow:**
1. Encrypt your `secrets.yaml` or `terraform.tfvars` file with SOPS + Age
2. Safely push the encrypted file to Gitea
3. When Ansible or Terraform runs, they use the Age private key stored only on Athena
   to decrypt the values on the fly

The private key never leaves Athena. The encrypted file is safe to commit.

---

## What Gets Encrypted

- `terraform.tfvars` — Proxmox API token, any provider secrets
- `secrets.yaml` — UniFi credentials used by Ansible
- Any file with passwords, tokens, or API keys before it touches Git

---

## Setup

**Install Age:**
```sh
apt install age
```

**Generate a keypair:**
```sh
age-keygen -o ~/.config/sops/age/keys.txt
```

**Configure SOPS** (`.sops.yaml` in repo root):
```yaml
creation_rules:
  - path_regex: secrets\.yaml$
    age: "<your-age-public-key>"
  - path_regex: terraform\.tfvars$
    age: "<your-age-public-key>"
```

**Encrypt a file:**
```sh
sops --encrypt --in-place secrets.yaml
```

**Decrypt / edit in place:**
```sh
sops secrets.yaml
```

---

## Terraform-Specific

```sh
# Encrypt before pushing
sops --encrypt terraform.tfvars > terraform.tfvars.enc

# Add to .gitignore
echo "terraform.tfvars" >> .gitignore
```

The encrypted `.enc` file is safe to commit. Terraform itself reads the decrypted
values at runtime via the SOPS provider or a pre-run decrypt step.

---

## Git Rules (Non-Negotiable)

```gitignore
# Never commit these
terraform.tfvars
terraform.tfvars.json
*.tfstate
*.tfstate.backup
.terraform/
secrets.yaml
```

> [!DANGER]
> Never commit plaintext secrets to Git. Once a secret is in Git history,
> it's compromised — rotation is required even if you delete the file.
