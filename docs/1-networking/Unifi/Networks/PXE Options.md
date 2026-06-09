> [!WARNING] Archived — netboot is abandoned
> Nodes are installed via [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md), not PXE.
> The DHCP boot options here are no longer needed; see the
> [post-mortem](../../Netboot/README.md). Kept for reference only — the switch-port table
> at the bottom is still accurate for the physical layout.

UniFi-side configuration for PXE booting nodes on VLAN 99. For Libre Potato setup, boot procedure, and fallbacks see [Netboot/](../../Netboot/README.md).

---

## UniFi DHCP Options

Set on the Provisioning VLAN (99) in UniFi:
Settings → Networks → Provisioning → DHCP → Network Boot (enable checkbox)

| UniFi Field | Value | Equivalent DHCP Option |
| --- | --- | --- |
| Server IP (first field) | `10.10.99.99` | Option 66 / next-server |
| Boot File URL (second field) | `netboot.xyz.efi` | Option 67 / boot filename |

> [!IMPORTANT]
> The boot filename must be `netboot.xyz.efi` — a plain filename, not an HTTP URL.
> If you put an HTTP URL (e.g. `http://...`) in this field, UEFI interprets it as UEFI
> HTTP boot and tries to execute the iPXE script as an EFI binary. It is not an EFI binary.
> The node will hang on "Start HTTP boot over IPv4" and never reach the installer.

---

## Provisioning Flow

1. Plug node into the dedicated provisioning port (UXG Max port 3, VLAN 99 access)
2. Power on — DHCP assigns a `10.10.99.x` address and sends next-server + boot filename
3. UEFI downloads `netboot.xyz.efi` via TFTP from 10.10.99.99
4. iPXE starts, looks for a MAC-specific boot file via TFTP (`MAC-<hexmac>.ipxe`)
5. MAC file found → loads vmlinuz + initrd + Proxmox ISO → automated install begins
6. Proxmox installer fetches the node's TOML answer file from 10.10.99.99:8080
7. Install completes (~5–10 min), node reboots with static management IP
8. Move cable from port 3 to its permanent trunk port on USW Flex Mini

> [!NOTE]
> The Libre Potato stays permanently on VLAN 99 — no reason to decommission it.
> Port 3 on the UXG Max stays permanently as a VLAN 99 access port. Any future
> node that needs provisioning just gets plugged in there first. (Access Port only)

---

## Switch Port Assignments

###### UXG Max

| Port | Mode   | Device                | Native VLAN | Tagged VLANs | IP                   | Notes                                                                                                                             |
| ---- | ------ | --------------------- | ----------- | ------------ | -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Access | Synology              | 10          | All          | Tailscale            | Temporary — becoming available soon                                                                                               |
| 2    | Trunk  | Libre Potato (SUNSET) | 10          | All          | 10.10.99.99 (SUNSET) | Netboot server. Native VLAN 99 so Libre Potato gets provisioning DHCP on boot. Unplug for Mac management access during bootstrap. |
| 3    | Trunk  | —                     | 10          | All          | —                    | Dedicated provisioning port. VLAN 99 only — plug node in here to PXE boot.                                                        |
| 4    | Trunk  | Uplink                | 10          | All          | —                    | USW Flex Mini (port 5)                                                                                                            |
| 5    | —      | Uplink                | —           | —            | DHCP                 | Comcast WAN                                                                                                                       |

###### USW Flex Mini

| Port | Mode  | Device    | Native VLAN | IP         | Notes            |
| ---- | ----- | --------- | ----------- | ---------- | ---------------- |
| 1    | Trunk | pve-srv-1 | 10          | 10.10.10.1 |                  |
| 2    | Trunk | pve-srv-2 | 10          | 10.10.10.2 |                  |
| 3    | Trunk | pve-srv-3 | 10          | 10.10.10.3 |                  |
| 4    | Trunk | pve-srv-4 | 10          | 10.10.10.4 |                  |
| 5    | Trunk | Uplink    | N/A         | —          | UXG Max (port 4) |
