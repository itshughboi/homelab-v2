# [ARCHIVED] UniFi EdgeRouter 4

> **Status: Archived.** Not current hardware. Kept as CLI reference — the DHCP/PXE
> option patterns translate to other routers if needed.

---

## Provisioning Network Setup (eth1)

```sh
set interfaces ethernet eth1 address 10.10.99.254/24
```

Verify:
```sh
show interfaces ethernet eth1
```

---

## PXE / DHCP Options

```sh
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 default-router 10.10.99.254
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 dns-server 1.1.1.1
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 lease 86400
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 start 10.10.99.50 stop 10.10.99.98
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 next-server 10.10.99.100
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 bootfile-name netboot.xyz.efi
```

**Optional — static IP for netboot device:**
```sh
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 static-mapping NETBOOT-MAC ip-address 10.10.99.100
set service dhcp-server shared-network-name PROVISIONING subnet 10.10.99.0/24 static-mapping NETBOOT-MAC mac-address AA:BB:CC:DD:EE:FF
```

**Save:**
```sh
commit
save
exit
```

**Verify DHCP leases:**
```sh
show dhcp leases
```
