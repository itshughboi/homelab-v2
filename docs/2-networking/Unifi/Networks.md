| Name         | VLAN ID | CIDR           | Notes                     | Notes                   |
| ------------ | ------- | -------------- | ------------------------- | ----------------------- |
| Management   | 1       | 10.10.10.0/24  | SSH, Web UI, Unifi, Bind9 | PXE Boot enabled        |
| Cluster      | 2       | 10.10.20.0/24  | Corosync                  | QoS / isolated          |
| k3s          | 3       | 10.10.30.0/24  |                           |                         |
| Storage      | 4       | 10.10.40.0/24  | TrueNAS, PBS, Longhorn    | Jumbo Frames / isolated |
| VPN          | 8       | 10.10.80.0/24  | Tailscale                 |                         |
| Torrent      | 49      | 172.16.20.0/24 |                           |                         |
| Provisioning | 99      | 10.10.99.0/24  | Netboot                   |                         |
