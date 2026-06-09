> **Not in use** — current provisioning is [Ventoy USB](Ventoy.md) + Proxmox answer files.
> MAAS was evaluated as the "proper" netboot-style tool but ruled out for now: consumer
> mini PCs have no IPMI/BMC (so no remote power-on, MAAS's main draw) and it's too heavy to
> host on the ARM Libre Potato. See the [netboot post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md).
> This doc is reference material if MAAS is ever reconsidered (e.g. the cluster grows or
> nodes with IPMI are added).

---

# MAAS — Metal as a Service

MAAS is Canonical's bare-metal provisioning platform. It turns physical servers into an on-demand resource pool — you enlist machines, and MAAS handles PXE boot, OS install, storage layout, and network config automatically. Think of it as the homelab equivalent of AWS EC2, but for physical hardware you own.
 
---

## What it does

MAAS manages the full lifecycle of a bare-metal machine:

1. **Enlist** — plug a machine in, it PXE boots into a MAAS ephemeral environment, reports its hardware (CPU, RAM, NICs, disks) back to the MAAS controller
2. **Commission** — MAAS runs hardware tests and inventories the machine
3. **Deploy** — pick an OS (Ubuntu, CentOS, custom image), MAAS PXE boots it again and installs fully unattended
4. **Release** — wipe and return the machine to the pool for redeployment

Every step is API-driven and scriptable. You can deploy a machine with one CLI command or API call.

---

## How it works

MAAS replaces your DHCP server (or integrates with it) and runs a PXE/TFTP server. Machines boot into a MAAS-controlled iPXE environment.

```
Machine powers on
    → DHCP points to MAAS rack controller
    → MAAS serves iPXE via TFTP
    → Machine boots into MAAS ephemeral Ubuntu (squashfs in RAM)
    → MAAS agent inventories hardware, reports to region controller
    → On deploy: MAAS streams OS image directly to disk, configures cloud-init
    → Machine reboots into installed OS
```

**Components:**

| Component | Role |
| --- | --- |
| Region controller | API, web UI, PostgreSQL database, DNS |
| Rack controller | DHCP, TFTP/PXE, image cache — sits close to the machines |
| BMC / IPMI | Optional but powerful — MAAS can power cycle machines remotely without physical access |

In a homelab, both region and rack run on the same machine (usually an LXC container or VM).

---

## Why it would be useful here

The current Ventoy USB setup is fine for a static cluster where nodes rarely change. MAAS becomes compelling when:

- **You're adding/replacing nodes frequently** — no manual TOML editing or MAC mapping. Enlist once, deploy on demand.
- **You want hardware inventory built-in** — MAAS tracks CPU, RAM, NICs, disks per machine automatically. No separate inventory files.
- **You want remote power control** — with IPMI/BMC configured, you can power on/off/reset machines from the MAAS UI or API without touching them physically.
- **You want to reprovision fast** — release a machine, redeploy with a different OS image in minutes. Useful for testing different Proxmox versions or rebuilding from scratch.
- **You want Terraform integration** — the [MAAS Terraform provider](https://registry.terraform.io/providers/maas/maas/latest) lets you `terraform apply` to deploy a physical machine the same way you'd spin up a VM.

---

## How to implement

### 1. Run MAAS in an LXC container

Create an Ubuntu 22.04 LXC on pve-srv-1 (MAAS works better on 22.04 than 24.04 with snap):

```sh
# Inside the LXC
apt install snapd
snap install --channel=3.7 maas

# Initialize (single-node: region + rack together)
maas init region+rack --database-uri "postgres://maas:maas@localhost/maasdb" \
  --maas-url http://<lxc-ip>:5240/MAAS
```

### 2. Configure DHCP

Either let MAAS control DHCP on VLAN 99 (replaces UniFi's DHCP on that VLAN), or run MAAS in "external DHCP" mode and point your existing DHCP at the MAAS rack controller for PXE. The cleaner path for this setup is to keep UniFi DHCP and configure MAAS to use it:

- Disable DHCP on VLAN 99 in UniFi
- Enable MAAS DHCP on the rack controller for the `10.10.99.0/24` subnet
- MAAS becomes the sole DHCP/PXE authority on VLAN 99

### 3. Enlist machines

Plug a machine into the provisioning port (UXG Max Port 3, VLAN 99). Power it on — it PXE boots into MAAS and appears in the UI under **Machines → New**. MAAS inventories the hardware automatically.

### 4. Commission and deploy

```sh
# Via CLI (after installing maas CLI and logging in)
maas admin machines read | jq '.[].hostname'

# Commission a machine
maas admin machine commission <system-id>

# Deploy Proxmox (requires custom image — see below)
maas admin machine deploy <system-id> osystem=custom distro_series=proxmox-8
```

### 5. Custom Proxmox image

MAAS ships Ubuntu images out of the box. For Proxmox you need a custom image:

1. Build a Proxmox cloud image with Packer (already in `packer/`)
2. Upload to MAAS: Settings → Images → Custom Images → Upload
3. Deploy using `osystem=custom distro_series=<your-image-name>`

Alternatively, deploy Ubuntu via MAAS and then use Ansible to install Proxmox on top — simpler than a custom image.

### 6. Terraform integration

```hcl
terraform {
  required_providers {
    maas = {
      source  = "maas/maas"
      version = "~> 2.0"
    }
  }
}

provider "maas" {
  api_version = "2.0"
  api_key     = var.maas_api_key
  api_url     = "http://<maas-ip>:5240/MAAS"
}

resource "maas_machine" "pve_srv_5" {
  hostname     = "pve-srv-5"
  # MAAS deploys the OS, then Ansible/Terraform takes over
}
```

---

## MAAS vs current Ventoy setup

| | Ventoy USB (current) | MAAS |
| --- | --- | --- |
| Setup complexity | Low | Medium-high |
| Hardware inventory | Manual (Inventory/ files) | Automatic |
| Remote power control | No (physical access needed) | Yes (**requires** IPMI/BMC — mini PCs lack it) |
| Reprovisioning speed | Re-flash USB / boot prepared ISO | One command or API call |
| Terraform integration | No | Yes (first-party provider) |
| Physical touch per node | Plug in USB (same trip as cabling) | Power button once (no IPMI) → zero-touch (with IPMI) |
| Fits a static 4-node cluster | ✅ | Overkill |
| Fits a growing/dynamic cluster | Gets tedious | ✅ (if nodes have IPMI) |

**Bottom line:** for a stable 4-node consumer cluster with no IPMI, Ventoy is the right call — MAAS's zero-touch power management (its main advantage over a USB) needs BMC hardware these nodes don't have. If the cluster grows past ~6 nodes or you add machines with IPMI/Redfish, MAAS starts paying for itself.
