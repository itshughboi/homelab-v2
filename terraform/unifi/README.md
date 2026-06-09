# UniFi Terraform — SUNSET (reference only)

> [!WARNING] Not in use — UniFi is managed manually
> The UniFi network is configured **by hand in the UI**, not by Terraform — see
> [docs/1-networking/Unifi/](../../docs/1-networking/Unifi/Overview.md). This workspace is kept
> as a **reference implementation** in case the network is ever moved to IaC. It is not applied,
> and it still encodes pre-sunset bits (e.g. the netboot/PXE provisioning VLAN). The docs — not
> this code — are the source of truth for the live network.

Models UniFi infrastructure as code: VLANs, firewall rules, port profiles, DHCP reservations,
PXE boot, and DNS overrides — for reference.

---

## Directory layout

```
terraform/unifi/
├── essentials/     # Active workspace — everything UniFi manages
│   ├── main.tf              # Provider + VLAN/network resources
│   ├── locals.tf            # VLAN definitions
│   ├── firewall.tf          # Firewall rule resources
│   ├── firewall_rules.tf    # Rule logic (allow/deny matrix)
│   ├── ports.tf             # Switch port profiles (trunk, provisioning)
│   ├── dhcp-reservations.tf # MAC→IP pins for Proxmox nodes
│   ├── dns-records.tf       # UniFi DNS overrides for pve-srv-*.hughboi.cc
│   ├── variables.tf         # Input variables
│   └── terraform.tfvars.example
└── bpg/            # Reference only — BGP exploration, not deployed
```

---

## Networks managed

| Name | VLAN | Subnet | DHCP | Purpose |
|------|------|--------|------|---------|
| management | 10 | 10.10.10.0/24 | Static (reservations) | SSH, web UIs, Proxmox |
| cluster | 20 | 10.10.20.0/24 | Off | Proxmox Corosync |
| k3s | 30 | 10.10.30.0/24 | Off | k3s pods + services |
| storage | 40 | 10.10.40.0/24 | Off | TrueNAS NFS/iSCSI |
| torrent | 49 | 172.16.20.0/24 | On | Isolated media VLAN |
| provisioning | 99 | 10.10.99.0/24 | On (100–200) | PXE boot only |

---

## Setup

### 1. Get UniFi API credentials

**Cloud-managed (recommended):**
UniFi → Admin & Users → API Keys → Create key

**Self-hosted controller:**
Create a Limited Admin account with 2FA disabled (required for API access).

### 2. Configure variables

```bash
cd terraform/unifi/essentials
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars    # fill in api_url + credentials
```

`terraform.tfvars` is in `.gitignore` — never commit it.

### 3. Init and apply

```bash
terraform init
terraform plan    # always review — network changes affect live traffic
terraform apply
```

---

## Firewall rules

Rules are defined in `firewall_rules.tf` and applied by `firewall.tf`. Zone-based logic:

| Source | Destination | Ports | Action |
|--------|-------------|-------|--------|
| management | management, cluster, storage, provisioning | 22,80,443 TCP | allow |
| cluster | cluster | 5404-5405 UDP | allow (Corosync) |
| k3s | storage | 2049,3260 TCP+UDP | allow (NFS + iSCSI) |
| k3s | management | 53 TCP+UDP | allow (DNS) |
| provisioning | provisioning | 67-68,69,80,443 | allow (DHCP+TFTP+HTTP) |
| provisioning | management | 53 TCP+UDP | allow (DNS) |
| torrent | management, cluster, storage, provisioning | ALL | **deny** |
| (all) | (all) | — | established/related: allow (rule 100) |

Custom rule indexes start at 2000 to stay above UniFi built-in rules (1000–1999).

---

## DHCP reservations

Proxmox nodes get static IPs via MAC reservation (`dhcp-reservations.tf`):

| Host | MAC | IP |
|------|-----|----|
| pve-srv-1 | 04:7c:16:87:65:66 | 10.10.10.1 |
| pve-srv-2 | c8:ff:bf:00:80:7c | 10.10.10.2 |
| pve-srv-3 | 1c:83:41:40:ff:0b | 10.10.10.3 |
| pve-srv-4 | c8:ff:bf:03:f3:50 | 10.10.10.4 |

Note: PXE boot uses a different NIC port (consecutive MACs on dual-port adapters). The boot-port MACs are mapped in `bootstrap/netbootxyz/config/local.ipxe`.

---

## PXE boot

Only the **provisioning VLAN** (99) has PXE enabled:
- DHCP option 66 (next-server) → `10.10.99.100` — machine running netboot.xyz
- Boot file: `netboot.xyz.kpxe`

The `management-trunk` port profile (applied to Proxmox switch ports) carries VLANs 10/20/30/40 tagged. Bare metal plugged into the `provisioning-only` port profile gets VLAN 99 and auto-PXE boots.

---

## Day-2 operations

**Add a VLAN:** Add to `local.networks` in `locals.tf`, add firewall rules if needed, apply.

**Add a DHCP reservation:** Add to `local.pve_nodes` in `dhcp-reservations.tf`, apply.

**Add a DNS override:** Add `unifi_dns_record` to `dns-records.tf`, apply.

---

## About `bpg/`

Contains a BGP config for UniFi (routing MetalLB service IPs via BGP). **Not deployed** — MetalLB L2 ARP mode was chosen instead as it requires no router config. Kept as reference. Cannot be applied as-is (no provider config or variables).
