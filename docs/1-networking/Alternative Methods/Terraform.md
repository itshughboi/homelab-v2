# [ARCHIVED] Terraform — UniFi Network Management

> **Status: Archived.** Terraform is no longer the active tool for UniFi/network management.
> Ansible is the source of truth. See [`04_Infrastructure_as_Code/01_IaC_Philosophy.md`](../04_Infrastructure_as_Code/01_IaC_Philosophy.md)
> for the reasoning.
>
> Terraform is still used for Proxmox VM provisioning and Bind9 DNS integration —
> this archive covers the UniFi piece only.

Documentation: https://registry.terraform.io/providers/ubiquiti-community/unifi/latest/docs

---

> [!DANGER] If you ever run `terraform apply` against UniFi again
> Terraform tracks objects in `.tfstate`. Changes made in the UniFi UI are NOT synced back.
> If you make UI changes and then run `apply`, Terraform will revert them.
> Only run `terraform apply` ONCE if using it as a bootstrap tool, then stop.

---

## Why It Was Shelved

Terraform keeps a `.tfstate` file as the authoritative record of what exists.
This creates a few problems in a homelab context:

- **Drift is a constant fight.** If you make any change in the UniFi UI — even a small one —
  Terraform no longer matches reality. You have to retroactively add that change to your
  Terraform files before the next `apply`, or Terraform will revert it.
- **Debugging has too many layers.** When something breaks, you're troubleshooting whether
  it's the UniFi Controller, the UniFi API, the Terraform provider, or the Terraform state file.
- **State file portability.** If you bootstrap from your laptop, the state file lives on your
  laptop. Moving it to Athena is a manual step that's easy to mess up.

---

## Why Ansible Works Better Here

Ansible is idempotent by nature — it says "apply these changes if the current state doesn't
match." This means:

- You can make changes in either the UniFi UI **or** Ansible — Ansible will skip anything
  already configured correctly
- **UniFi is authoritative**, not Terraform. Ansible describes desired state, not owns state.
- No state file to manage or accidentally corrupt


## File Layout

```
/terraform/unifi/
├── providers.tf       # UniFi connection details
├── variables.tf       # Variable definitions
├── terraform.tfvars   # Actual MACs and IPs (never commit this)
├── locals.tf          # VLANs
├── firewall.tf        # Firewall rules
└── main.tf            # Logic to create nodes
```

## Authentication

- **API Key** (Cloud-Managed): UniFi → Admin & Users → Terraform → Create API Key
- **Local Account** (Self-Hosted): Limited Admin, 2FA disabled

## Running It

```sh
git clone https://github.com/itshughboi/iac.git
cd /iac/terraform/unifi/essentials

terraform init
terraform plan
terraform apply
```

> [!DANGER] Add `terraform.tfvars` to `.gitignore` — NEVER commit this file.

---

## MAC Discovery Methods

### UniFi API

> [!WARNING] API login does not work if UniFi MFA is enabled.

**Authenticate:**
```sh
curl -k -c unifi_cookie.txt \
     -H "Content-Type: application/json" \
     -X POST \
     -d '{"username":"hughboi", "password":"CHANGEME"}' \
     "https://10.10.10.10:8443/api/login"
```

**Discover:**
```sh
curl -k -b unifi_cookie.txt \
     -X GET \
     "https://10.10.10.10:8443/api/s/default/stat/sta" | \
     jq '.data[] | select(.is_wired == true) | {mac: .mac, vendor: .oui, ip: .ip, port: .sw_port, hostname: .hostname}'
```

### Nmap

> Must be on the same subnet to get MAC addresses from nmap.

```sh
sudo nmap -sn -PR 10.10.10.0/24 -vv --stats-every 5s
```

### Terraform Import

```sh
terraform import 'unifi_user.proxmox_nodes["pve-srv-1"]' aa:bb:cc:11:22:33
terraform import 'unifi_user.proxmox_nodes["pve-srv-2"]' 11:22:33:44:55:66
```

### `terraform.tfvars` Example

```hcl
nodes = {
  "pve-srv-1" = { mac = "aa:bb:cc:11:22:33", ip = "10.10.10.1" }
  "pve-srv-2" = { mac = "11:22:33:44:55:66", ip = "10.10.10.2" }
  "pve-srv-3" = { mac = "22:33:44:55:66:77", ip = "10.10.10.3" }
  "pve-srv-4" = { mac = "33:44:55:66:77:88", ip = "10.10.10.4" }
}
```
