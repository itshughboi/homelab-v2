The Libre Potato (`10.10.99.99`) serves automated Proxmox installs to all nodes via iPXE over VLAN 99. It pulls updates from Gitea every 5 minutes via a systemd timer.

For UniFi DHCP options and switch port assignments see [PXE Options.md](../Unifi/Networks/PXE%20Options.md).

| File | Contents |
| --- | --- |
| [Setup.md](Setup.md) | BIOS prereqs, Libre Potato first-time setup, auto-refresh timer |
| [Nodes.md](Nodes.md) | Register a node, verify, boot procedure, adding nodes later |
| [Fallback.md](Fallback.md) | Macbook and Ventoy fallback options |

---

## Boot Chain

```
Node powers on
    → DHCP (VLAN 99) returns Option 66: 10.10.99.99, Option 67: ipxe.efi
    → Libre Potato serves ipxe.efi over HTTP port 8080
    → iPXE loads, runs autoexec.ipxe → local.ipxe
    → local.ipxe reads node MAC → maps to hostname
    → node pulls its TOML: http://10.10.99.99:8080/proxmox/pve-srv-X.toml
    → Proxmox installs automatically, node receives permanent IP (VLAN 10)
    → Move cable from provisioning port to permanent trunk port
```

### Why netboot.xyz over USB

| Method | Pros | Cons |
| --- | --- | --- |
| netboot.xyz ✅ | No USB juggling, config in Git, fast | Infra must stay healthy |
| Ventoy USB | Works without network | Manual, slow at scale |
| BMC/IPMI | Enterprise break-glass | Requires enterprise hardware |
