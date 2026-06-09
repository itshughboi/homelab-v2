# [ARCHIVED] PXE / DHCP Options

> [!WARNING] Not in use
> Provisioning moved to [Ventoy USB](../Ventoy.md); netboot/PXE is
> [abandoned](../../../1-networking/Alternative%20Methods/Netboot/README.md). The DHCP boot options below
> (66/67 on VLAN 99) are **no longer needed** and can be removed from UniFi. Kept for
> reference only.

---

## DHCP Boot Options (VLAN 99)

Set on the DHCP options for the Provisioning VLAN (99).

| Option | Value | Description |
| --- | --- | --- |
| 66 | 10.10.99.99 | TFTP/HTTP boot server (Libre Potato) |
| 67 | ipxe.efi | Boot filename |

> [!NOTE]
> Setting Option 67 to `netboot.xyz.efi` instead loads the interactive netboot menu
> and requires manual OS selection. Useful as a fallback if automated boot fails.

---

## Proxmox Virtual Interface DHCP

| Virtual Interface | Target VLAN | Gateway | MTU | DHCP Option 67 (Next-Server) |
| --- | --- | --- | --- | --- |
| vmbr1.10 | 10 | 10.10.10.254 | 1500 | 10.10.99.99 |
| vmbr1.20 | 20 | None | 1500 | |
| vmbr1.40 | 40 | None | 9000 | |

---

## If UniFi is Not Available

If UniFi DHCP boot options aren't configured yet, SSH or console into the router directly
and set them manually. See the archived EdgeRouter 4 doc for the CLI commands as a reference
pattern — the option names translate to whatever router is in use.

For Microtik specifically:
- Next Server: IP of netboot server (10.10.99.99)
- Boot File Name: `netboot.xyz.efi`

→ Console cable instructions if needed: [Using Console Cable.md](../../../1-networking/Alternative%20Methods/Using%20Console%20Cable.md)
