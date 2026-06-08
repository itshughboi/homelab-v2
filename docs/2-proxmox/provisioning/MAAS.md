> **DEPRECATED** — MAAS was explored as a bare-metal provisioning tool but was replaced
> by netboot.xyz + Proxmox answer files (`.toml`). The current PXE boot chain is documented
> in `bootstrap/netbootxyz/README.md` and `docs/1. Prep/Netboot Setup.md`.

**Metal As A Service**
1. Create LXC container (ubuntu)
2. Install snapd (unless I go apt package route, but doesn't work well on 24.04)
```
apt install snapd
# install maas version 3.7
snap install --channel=3.7 maas
```
