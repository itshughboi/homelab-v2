---
title: "Fallback"
---

> [!WARNING] Historical — netboot is abandoned
> Nodes are installed via [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md) — that is now
> the **primary** method, documented in its own doc (don't look for it here). The one item
> below is a netboot-era fallback, kept for reference only. See the [post-mortem](README.md).

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

> [!NOTE]
> The Ventoy USB method that used to live here is now the **primary** install method —
> see [provisioning/Ventoy.md](../../../2-proxmox/provisioning/Ventoy.md). The old version on
> this page was incomplete (it skipped `proxmox-auto-install-assistant`), so it was removed
> rather than left to mislead.
