## Macbook as Temporary Netboot Server

Use when Libre Potato is down but you still want network-based provisioning. Runs until you close the terminal — no permanent setup needed.

1. Plug Macbook into UXG Max Port 3 (VLAN 99 access port) — it gets assigned `10.10.99.x/24`
2. Run the ephemeral container:

```sh
docker run --rm -it \
  -p 80:80 \
  -p 69:69/udp \
  --name netbootxyz \
  netbootxyz/netbootxyz
```

3. Boot nodes normally — they PXE boot to your Macbook instead of Libre Potato
4. Close the terminal when done — container is automatically removed

---

## Ventoy USB Fallback

Use when Libre Potato is unavailable or you're rebuilding from zero:

1. Format USB with Ventoy
2. Rename main partition to `PROXMOX_AIC` — **required** for the installer to find the answer file
3. Copy Proxmox VE ISO to USB
4. Place `pve-srv-X.toml` renamed to `answer.toml` adjacent to the ISO
5. Boot from USB → select **Automated Installation** from the Proxmox boot menu
