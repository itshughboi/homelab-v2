# Switch Port Assignments

---

## UXG Max

| Port | Mode | Device | VLAN | IP | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Access | — | — | — | Available |
| 2 | Access | — | 10 | — | **Available** (Management) — was Libre Potato / netboot server |
| 3 | Access | — | 10 | — | **Available** (Management) — was the provisioning port |
| 4 | Trunk | Uplink to USW Flex Mini | N/A | N/A | Port 5 on Flex Mini |
| 5 | — | Comcast WAN | N/A | DHCP | WAN uplink |

> [!NOTE] Netboot abandoned — ports returned to Management
> Ports 2 and 3 (and VLAN 99) were the PXE provisioning setup. Nodes now install via
> [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md) and plug straight into their
> permanent trunk port on the Flex Mini — see the [post-mortem](../../Alternative%20Methods/Netboot/README.md).
> Both ports are now reassigned to **Management (VLAN 10)** as general-purpose access ports.
> The provisioning **VLAN 99** is retired — remove it in UniFi once nothing else references it.

---

## USW Flex Mini

| Port | Mode | Device | VLANs | IP | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Trunk | pve-srv-1 | All (10,20,30,40) | 10.10.10.1 | Trunk allows all VLANs |
| 2 | Trunk | pve-srv-2 | 10, 20, 30, 40 | 10.10.10.2 | |
| 3 | Trunk | pve-srv-3 | 10, 20, 30, 40 | 10.10.10.3 | |
| 4 | Trunk | pve-srv-4 | 10, 20, 30, 40 | 10.10.10.4 | |
| 5 | Trunk | Uplink to UXG Max | N/A | — | Port 4 on UXG Max |

---

## Unifi Controller Access

Default credentials (only relevant on fresh hardware before Ansible configures it):

```sh
username: ubnt
password: ubnt
```

SSH into controller:
```sh
ssh ubnt@<unifi-ip>
configure
```

> After initial setup, the local Ansible admin account replaces the default.
> Cloud account will not work with Ansible — must be a local account.
