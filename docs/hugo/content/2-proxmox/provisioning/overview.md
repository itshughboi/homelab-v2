---
title: "Provisioning Overview"
---

# Provisioning Overview

> Nodes are installed via **Ventoy USB** — see [Ventoy.md](Ventoy.md) for the full method.
> Netboot/PXE was tried and abandoned; the [post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md)
> records why so it isn't re-attempted.

---

## How nodes are provisioned

| Method | How It Boots | Status |
| --- | --- | --- |
| **Ventoy USB** ✅ | USB → Proxmox ISO (answer baked in) → automated install | **In use** |
| Classic PXE / Netboot | DHCP → iPXE → installer | Abandoned — see [post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md) |
| MAAS | DHCP → MAAS PXE → image to disk | Evaluated — needs IPMI + heavy infra, [details](sunset/MAAS.md) |
| BMC / IPMI / Redfish | API → mount ISO → autoinstall | N/A — consumer mini PCs have no BMC |

The short version: netboot.xyz is an interactive menu tool, not a provisioning pipeline,
and loading a 1.8 GB ISO as an initrd over the network proved too fragile. Ventoy boots
the ISO as real media and the answer file is baked into the ISO with
`proxmox-auto-install-assistant`. The per-node TOMLs still live in git.

---

## Flow (summary)

```
pve-srv-1 (amd64): prepare-iso --fetch-from iso --answer-file pve-srv-X.toml
    ↓ copy prepared ISO onto Ventoy USB
Boot node from USB → Automated Installation → installs onto 10.10.10.X
    ↓
Ansible/Terraform take over (network, cluster, VMs)
```

Because the answer files set a **static** management IP, you plug the node straight into
its permanent trunk port (VLAN 10) — no VLAN 99 provisioning step and no cable move. Full
steps in [Ventoy.md](Ventoy.md).

---

## BIOS Prerequisites (per node)

1. **USB boot enabled**, USB first in boot order
2. Secure Boot **OFF**

(Network/PXE boot is no longer required.)
