# Networks

| Name | VLAN ID | CIDR | Gateway | Notes |
| --- | --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | 10.10.10.254 | SSH, Web UI, UniFi, Bind9. PXE boot enabled. |
| Cluster | 20 | 10.10.20.0/24 | None | Corosync only. QoS DSCP 46. DHCP disabled. |
| k3s | 30 | 10.10.30.0/24 | 10.10.30.254 | Workloads, MetalLB, Longhorn. DHCP pool starts at .200. |
| Storage | 40 | 10.10.40.0/24 | 10.10.40.254 | Jumbo Frames (MTU 9000). Outbound updates only. DHCP disabled. |
| IoT | 50 | 10.10.50.0/24 | 10.10.50.254 | Smart home devices. Isolated — only Home Assistant can initiate in. |
| Torrent | 49 | 172.16.20.0/24 | 172.16.20.254 | Airgapped from all RFC1918. WAN only. |
| VPN | 80 | 10.10.80.0/24 | 10.10.80.254 | Tailscale subnet router. |
| Guest | — | 172.69.69.0/24 | 172.69.69.254 | AP guest WiFi. Client isolation. Internet only. |
| Provisioning | 99 | 10.10.99.0/24 | 10.10.99.254 | PXE boot only. Short lease. |

See [VLANs + VMs.md](VLANs%20+%20VMs.md) for full DHCP ranges, mDNS settings, and per-VLAN notes.
