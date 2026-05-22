# proxmox-iso-ubuntu

Builds an Ubuntu Server 24.04 LTS (Noble) VM template on Proxmox using ISO autoinstall. The resulting template (VM ID 9999) is cloned by Terraform to create all k3s nodes.

---

## What it produces

A cloud-init–ready Ubuntu VM template with:
- QEMU guest agent installed (required for Proxmox IP reporting and graceful shutdown)
- Cloud-init configured with the Proxmox `ConfigDrive` datasource
- SSH authorized keys pre-installed
- No swap
- Clean machine-id and SSH host keys (reset at clone time, generated fresh per VM)

---

## Files

| File | Purpose |
|------|---------|
| `proxmox-iso-ubuntu.pkr.hcl.j2` | Jinja2 template of the Packer HCL build file |
| `templates.yaml` | Schema/metadata for the Semaphore UI template browser |
| `build.sh` | Renders the `.j2` template and runs `packer build` |
| `proxmox.pkrvars.sh.example` | Copy → `proxmox.pkrvars.sh`, fill in secrets |
| `http/user-data.j2` | Ubuntu autoinstall (cloud-config) served to the installer |
| `http/meta-data` | Required empty metadata file for cloud-init HTTP source |
| `files/99-pve.cfg` | Cloud-init datasource config (`ConfigDrive, NoCloud`) |

---

## Quick start

### 1. Create the Proxmox API token

```bash
# On a Proxmox node:
pveum user add packer@pve
pveum aclmod / -user packer@pve -role Administrator
pveum user token add packer@pve packer --privsep=0
# Save the token secret in Vaultwarden: "homelab / proxmox / packer-api-token"
```

### 2. Upload the Ubuntu ISO to Proxmox

In Proxmox UI: `pve-srv-1` → local storage → ISO Images → Download from URL:
```
https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso
```

Or upload manually via `scp`.

### 3. Configure variables

```bash
cp proxmox.pkrvars.sh.example proxmox.pkrvars.sh
$EDITOR proxmox.pkrvars.sh    # fill in PROXMOX_API_TOKEN_SECRET and SSH_PASSWORD
```

`proxmox.pkrvars.sh` is in `.gitignore` — never commit it.

### 4. Build

```bash
./build.sh
```

This renders the Jinja2 template, initialises Packer plugins, and runs the build (~10–15 minutes). The resulting template (VM ID 9999) appears in Proxmox on `pve-srv-1`.

Preview only (no build):
```bash
./build.sh --dry-run
```

### 5. Hand off to Terraform

```bash
cd ../../terraform/proxmox
terraform apply
```

Terraform clones VM 9999 to create all k3s masters, workers, and Longhorn nodes.

---

## How the build works

```
build.sh
   │
   ├─ Renders proxmox-iso-ubuntu.pkr.hcl.j2 → proxmox-iso-ubuntu.pkr.hcl
   │
   └─ packer build proxmox-iso-ubuntu.pkr.hcl
          │
          ├─ Creates VM on Proxmox, attaches ISO
          ├─ Starts HTTP server to serve http/user-data.j2 (rendered autoinstall config)
          ├─ Sends boot command to VM: autoinstall ds=nocloud-net;s=http://<packer-ip>:<port>/
          ├─ Ubuntu installer fetches user-data, performs automated install
          ├─ Packer SSH's in and runs shell provisioners:
          │     - Waits for cloud-init to finish
          │     - Removes SSH host keys (regenerated per-clone)
          │     - Resets machine-id (unique per-clone)
          │     - Cleans apt cache
          │     - Installs files/99-pve.cfg (Proxmox cloud-init datasource)
          └─ Stops VM and converts to template
```

---

## Updating the template

Rebuild when:
- A new Ubuntu 24.04.x point release is out (update `ISO_FILE` and `ISO_CHECKSUM`)
- You want to bake in additional packages (edit `http/user-data.j2` → `packages:`)

After rebuilding, existing clones are unaffected — Terraform only clones at `apply` time. To roll the change out, re-run `terraform apply` for the VMs you want to rebuild.

The [Ansible playbook `vm-template-refresh`](../../ansible/playbooks/proxmox/vm-template-refresh/) automates the ISO download and template rebuild.

---

## Dependencies

| Tool | Install |
|------|---------|
| `packer` | `brew install packer` |
| `python3` + `jinja2` | `pip3 install jinja2` |
| Proxmox API token | See step 1 above |
