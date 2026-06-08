UniFi-side configuration for PXE booting nodes on VLAN 99. For Libre Potato setup, boot procedure, and fallbacks see [Netboot.md](Netboot.md).

---

## UniFi DHCP Options

Set on the Provisioning VLAN (99) in UniFi:
Settings → Networks → Provisioning → DHCP → Network Boot (enable checkbox)

| UniFi Field | Value | Equivalent DHCP Option |
| --- | --- | --- |
| Server IP (first field) | `10.10.99.99` | Option 66 / next-server |
| Boot File URL (second field) | `http://10.10.99.99:8080/proxmox/local.ipxe` | Option 67 / boot filename |

> [!NOTE]
> Changing the boot file URL to point at `netboot.xyz.efi` loads the interactive menu
> and requires manual OS selection. Useful as a fallback if automated boot fails.

---

## Provisioning Flow

1. Plug node into the dedicated provisioning port (UXG Max port 3, VLAN 99 access)
2. Power on — DHCP assigns a `10.10.99.x` address and points to netboot (`10.10.99.99`)
3. Libre Potato serves iPXE binary + TOML config
4. Proxmox installs and configures automatically
5. Node receives its permanent IP via MAC reservation
6. Move cable from port 3 to its permanent trunk port on USW Flex Mini
7. Athena can now reach it on VLAN 10

> [!NOTE]
> The Libre Potato stays permanently on VLAN 99 — no reason to decommission it.
> Port 3 on the UXG Max stays permanently as a VLAN 99 access port. Any future
> node that needs provisioning just gets plugged in there first.

---

## Switch Port Assignments

###### UXG Max

| Port | Mode   | Device       | VLAN | IP          | Notes                               |
| ---- | ------ | ------------ | ---- | ----------- | ----------------------------------- |
| 1    | Access | Synology     | —    | Tailscale   | Temporary — becoming available soon |
| 2    | Access | Libre Potato | 99   | 10.10.99.99 | Netboot server, permanent           |
| 3    | Access | —            | 99   | —           | Dedicated provisioning port         |
| 4    | Trunk  | Uplink       | N/A  | N/A         | USW Flex Mini (port 5)              |
| 5    | —      | Uplink       | N/A  | DHCP        | Comcast WAN                         |

###### USW Flex Mini

| Port | Mode  | Device    | VLAN           | IP         | Notes            |
| ---- | ----- | --------- | -------------- | ---------- | ---------------- |
| 1    | Trunk | pve-srv-1 | 10, 30, 40     | 10.10.10.1 |                  |
| 2    | Trunk | pve-srv-2 | 10, 20, 30, 40 | 10.10.10.2 |                  |
| 3    | Trunk | pve-srv-3 | 10, 20, 30, 40 | 10.10.10.3 |                  |
| 4    | Trunk | pve-srv-4 | 10, 20, 30, 40 | 10.10.10.4 |                  |
| 5    | Trunk | Uplink    | N/A            | —          | UXG Max (port 4) |
