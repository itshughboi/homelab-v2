## Proxmox Terraform

Provisions Proxmox VMs via the [bpg/proxmox](https://github.com/bpg/terraform-provider-proxmox) provider. All k3s nodes (masters, workers, Longhorn storage) are managed here.

---

## Setup

### 1. Proxmox API Token (preferred over user password)

```bash
# In Proxmox UI:
# Datacenter → Permissions → Users → Add
#   Username: terraform@pve, Realm: pve
# Datacenter → Permissions → API Tokens → Add
#   User: terraform@pve, Token ID: terraform, Privilege Separation: unchecked
# Datacenter → Permissions → Add (User/API Token Permission)
#   Path: /, Token: terraform@pve!terraform, Role: Administrator

# Or via CLI on a Proxmox node:
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve terraform --privsep=0
```

Store the token secret in Vaultwarden — it's shown only once.

### 2. Create your tfvars file

```bash
cp terraform.tfvars.example terraform.tfvars
# Fill in: proxmox_api_url, proxmox_api_token, ssh_public_key, proxmox_nodes_*
```

> `terraform.tfvars` is in `.gitignore` — never commit it.

### 3. Packer template

The VM template (ID 9999) must exist before running Terraform. Build it with Packer first:
```bash
cd ../../packer/proxmox-iso-ubuntu
packer build .
```

### 4. Init and apply

```bash
terraform init
terraform plan    # always review before apply
terraform apply
```

---

## State Backend

See `backend.tf` for options. Default is local state (fine for solo use).

**Recommended**: Gitea HTTP backend — uses Gitea's built-in package registry, no S3 needed:
```bash
export TF_HTTP_PASSWORD=<gitea-api-token>
terraform init -migrate-state
```

> Never commit `terraform.tfstate` or `terraform.tfstate.backup` — both are in `.gitignore`.

---

## Day-2 Operations

### Add a new VM
1. Create a new `.tf` file (copy `athena.tf` as a template)
2. `terraform plan` to preview
3. `terraform apply` — Proxmox clones the template and boots the VM

### Resize a disk
```bash
# Terraform manages disk size — change the `size` in the .tf file, then:
terraform apply
# Proxmox resizes the disk; you still need to grow the partition inside the VM:
#   sudo growpart /dev/sda 1
#   sudo resize2fs /dev/sda1
```

### Destroy a single VM
```bash
terraform destroy -target=proxmox_virtual_environment_vm.k3s_master[0]
```

### Destroy everything
```bash
terraform destroy
# WARNING: this destroys all VMs defined in this directory
```

---

## VM Management Rules

- **Never edit Terraform-managed VMs in the Proxmox GUI.** Proxmox and Terraform share state only through the `.tfstate` file — GUI changes cause drift and `terraform apply` will revert them.
- If you need a one-off change, use `terraform import` first, then manage it via code.
- Snapshots are fine to take manually in the GUI — Terraform doesn't manage them.

---

## Node Map (current)

| Resource | VM IDs | IPs | Count |
|----------|--------|-----|-------|
| `k3s_master` | 601–603 | 10.10.30.1–3 | 3 |
| `k3s_worker` | 611–613 | 10.10.30.11–13 | 3 |
| `k3s_longhorn` | 621–623 | 10.10.30.51–53 | 3 |
| `dock_prod` | varies | 10.10.30.X | 1 |

IPs are assigned via Unifi DHCP reservations (keyed on MAC address) — not set in Terraform directly.

---

## Upgrading the Provider

```bash
# Update version in providers.tf, then:
terraform init -upgrade
terraform plan   # review any resource changes caused by provider upgrade
```

Renovate will open a PR when a new `bpg/proxmox` provider version is released.
