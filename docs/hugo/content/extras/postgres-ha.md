---
title: "postgres"
---


> **DEPRECATED** — Standalone Postgres HA with HAProxy LXC containers. Superseded by
> running Postgres inside k3s with CloudNativePG or as a sidecar, depending on the app.
> Kept for reference only.

Documentation Link: https://technotim.live/posts/postgresql-high-availability/

### Nodes
```
# postgres
postgres-1: 10.10.10.11/24 
postgres-2: 10.10.10.12/24
postgres-3: 10.10.10.13/24

# ha proxy
haproxy-1: 10.10.10.21/24
haproxy-2: 10.10.10.22/24
haproxy-3: 10.10.10.23/24
```


### Proxmox Infrastructure
Objective: Create a new LXC container for each postgresql + ha-proxy

##### Postgres LXC:
**General**
- Unprivileged container: Checked
- Nesting: Checked
**Template**
- Add ubuntu lxc template @ PVE-SRV-X -> Local -> CT Templates -> Templates
- Ubuntu 2x.xx LTS. 
**Disks**
- For testing I can use 10GB, but in production this should be 100GB+
**CPU**
- Cores: 2
**Memory**
- Memory: 1048MB
- Swap: 512MB


##### HA-Proxy LXC:
**General**
- Unprivileged container: Checked
- Nesting: Checked
**Template**
- Add ubuntu lxc template @ PVE-SRV-X -> Local -> CT Templates -> Templates
- Ubuntu 2x.xx LTS. 
**Disks**
- Can keep this on the lower end (25 - 50 GB)
**CPU**
- Cores: 1
**Memory**
- Memory: 512MB
- Swap: 512MB




