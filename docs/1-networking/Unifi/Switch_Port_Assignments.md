# Switch Port Assignments

---

## UXG Max

| Port | Mode | Device | VLAN | IP | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Access | — | — | — | Available |
| 2 | Access | Libre Potato (netboot) | 99 | 10.10.99.99 | Permanent |
| 3 | Access | — | 99 | — | Dedicated provisioning port — plug new nodes here first |
| 4 | Trunk | Uplink to USW Flex Mini | N/A | N/A | Port 5 on Flex Mini |
| 5 | — | Comcast WAN | N/A | DHCP | WAN uplink |

> Port 3 stays permanently as a VLAN 99 access port. Any future node that needs
> provisioning just gets plugged in here first.

---

## USW Flex Mini

| Port | Mode | Device | VLANs | IP | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Trunk | pve-srv-1 | 10, 40 | 10.10.10.1 | Storage on VLAN 40 |
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
