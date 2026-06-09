#### Proxmox
| Name      | IP         | Role            |
| --------- | ---------- | --------------- |
| pve-srv-1 | 10.10.10.1 | storage, docker |
| pve-srv-2 | 10.10.10.2 | k3s             |
| pve-srv-3 | 10.10.10.3 | k3s             |
| pve-srv-4 | 10.10.10.4 | k3s             |
***

#### Essentials
| Name        | VLAN | IP           | Gateway      |
| ----------- | ---- | ------------ | ------------ |
| truenas     | 10   | 10.10.10.5   | 10.10.10.254 |
| pbs         | 10   | 10.10.10.6   | 10.10.10.254 |
| athena      | 10   | 10.10.10.8   | 10.10.10.254 |
| dock-prod   | 10   | 10.10.10.10  | 10.10.10.254 |
| vpn-gateway | 80   | 10.10.80.254 | 10.10.80.254 |
***

#### k3s
| Name             | IP          |
| ---------------- | ----------- |
| k3s-master-1     | 10.10.30.1  |
| k3s-master-2     | 10.10.30.2  |
| k3s-master-3     | 10.10.30.3  |
| k3s-worker-1     | 10.10.30.11 |
| k3s-worker-2     | 10.10.30.12 |
| k3s-worker-3     | 10.10.30.13 |
| k3s-api-vip      | 10.10.30.30 |
| k3s-longhorn-vip | 10.10.30.50 |
| k3s-longhorn-1   | 10.10.30.51 |
| k3s-longhorn-2   | 10.10.30.52 |
| k3s-longhorn-3   | 10.10.30.53 |
| MetalLB Services | 10.10.30.60 |
| .                |             |
| traefik-vip      | 10.10.30.65 |
| pihole-vip       | 10.10.30.69 |
| .                |             |
| End MetalLB      | 10.10.30.99 
