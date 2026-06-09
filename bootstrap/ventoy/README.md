# Ventoy — Per-Node Auto-Install ISOs (rung A)

The zero-infrastructure automated path: bake each node's answer file into its own ISO, drop them
all on a Ventoy USB, boot the node, pick its ISO, walk away. No services to run.

Trade-off vs the [answer server](../proxmox-answer-server/README.md) (rung B): you rebuild a
node's ISO when its config changes, and you pick the node's ISO from the Ventoy menu (one
selection) rather than one generic ISO for all. For a small, rarely-reimaged cluster that's
fine; for heavy reimaging, rung B is nicer. Full comparison:
[provisioning/Ventoy.md](../../docs/2-proxmox/provisioning/Ventoy.md).

---

## Build the ISOs (on pve-srv-1 — amd64 tool)

```sh
./make-isos.sh proxmox-ve_9.1-1.iso
# → out/pve-srv-1-auto.iso … pve-srv-4-auto.iso
```

`make-isos.sh` loops every `pve-srv-*.toml` in `../netbootxyz/assets/proxmox/` through
`proxmox-auto-install-assistant prepare-iso --fetch-from iso`. Re-run it whenever a TOML changes.

Copy `out/*.iso` onto the Ventoy USB.

## Boot a node

1. Plug into its **permanent trunk port** (VLAN 10) — no cable move, the answer sets the static IP.
2. Boot from Ventoy → pick `pve-srv-X-auto.iso` → unattended install → reboots onto `10.10.10.X`.

## Optional — auto-boot (`ventoy.json`)

`ventoy.json` (copy to the USB root) sets a default ISO + menu aliases. Auto-boot picks **one**
default image, so it's most useful when you're **reimaging the same node repeatedly** during
testing — set that node's ISO as `VTOY_DEFAULT_IMAGE` and it boots with no keystrokes. For
mixed per-node installs you'll still pick from the menu.

> Confirm the `ventoy.json` key names / timeout option against the Ventoy control-plugin docs for
> your Ventoy version.
