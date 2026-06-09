# [ABANDONED] Netboot / PXE — Post-Mortem

> **Netboot is no longer used.** Nodes are installed via **Ventoy USB** —
> see [provisioning/Ventoy.md](../../2-proxmox/provisioning/Ventoy.md).
>
> This folder is kept as a record of what was tried and why it didn't work, so the
> same ground isn't re-trodden. [Setup.md](Setup.md), [Nodes.md](Nodes.md), and
> [Fallback.md](Fallback.md) describe the old PXE flow and are historical only.

The goal was GitOps-style bare-metal provisioning: push a per-node config to git, plug a
node in, have it install Proxmox automatically over the network. netboot.xyz was the tool.
It does not fit that goal — it's an **interactive boot menu**, not a provisioning pipeline.
Every problem below stems from bending it into a role it wasn't built for.

---

## What broke, in order

**1. DHCP option 67 as an HTTP URL → UEFI HTTP-boot trap.**
Setting the boot filename to `http://10.10.99.99:8080/proxmox/local.ipxe` makes UEFI treat
it as *UEFI HTTP boot* and try to execute the iPXE script as an EFI binary. It isn't one.
The node hangs on **"Start HTTP boot over IPv4."** The boot filename must be a plain TFTP
filename (`netboot.xyz.efi`) so the firmware downloads the iPXE binary first.

**2. Wrong file served from the wrong root (TFTP vs HTTP).**
`local.ipxe` lived in `config/` (TFTP root `/config/menus`) but was requested over HTTP,
whose root is `assets/`. Result: 404. The two volumes serve different trees and it's easy
to put a file where the requesting protocol can't see it.

**3. File ownership — silent `Permission denied`.**
dnsmasq (TFTP) runs **as UID 1000** inside the container. Any file created with `sudo`
(`sudo tee`, `sudo cp`) is `root:root` and dnsmasq **cannot read it** — it fails silently
in the logs and the node falls back to the interactive menu. Files from `git pull` get the
right ownership automatically; manually-created ones need `chown 1000:1000`.

**4. Stock netboot.xyz assets have no auto-install logic.**
The `vmlinuz`/`initrd` that netboot.xyz downloads boot the **interactive** Proxmox
installer. They contain none of the answer-file machinery. The real Proxmox method requires
running `proxmox-auto-install-assistant prepare-iso` and serving *that* prepared kernel/
initrd, booted with `proxmox-start-auto-installer`. The kernel params we were passing
(`proxmox-installer-opts=...`) were simply ignored.

**5. ISO-as-initrd over the network → "no device with valid ISO found."**
Proxmox PXE loads the **entire 1.8 GB ISO** as a second initrd (`initrd <url> /proxmox.iso`).
This is RAM-hungry and finicky about the cpio path. In practice the installer never found
the ISO. This same mechanism is what the interactive netboot menu uses too — so the menu
is **not** a safe fallback; it hits the same wall.

---

## Why not MAAS (the "right" netboot tool)

MAAS is purpose-built for this and has a Terraform provider — it would genuinely shine.
Two blockers at this scale:

- **No IPMI/BMC.** Consumer mini PCs lack it, so MAAS's killer feature (remote power-on,
  true zero-touch) is unavailable. Without it you're pressing the power button by hand
  anyway.
- **Heavy.** MAAS wants 4–8 GB RAM + real disk and to own DHCP on the provisioning VLAN.
  The Libre Potato (2 GB, SD card) can't host it; it'd have to run as a VM on pve-srv-1.
  That's a lot of infrastructure to install three more nodes that rarely get reimaged.

See [provisioning/MAAS.md](../../2-proxmox/provisioning/MAAS.md) for the full evaluation.

---

## The decision

For 4 consumer nodes you reimage rarely, **Ventoy + a baked-answer ISO** wins: it boots the
ISO as real media (no ISO-as-initrd fragility), the install is hands-off, and the per-node
TOMLs stay in git. You already touch each node to plug it in — a USB stick is the same trip.
All the real automation (network, cluster, VMs) already lives in Ansible/Terraform and is
unaffected.

**Knock-on cleanup** (no longer needed for provisioning):
- VLAN 99 DHCP boot options (66/67) — unused
- UXG Max Port 3 dedicated provisioning port — free to repurpose
- Libre Potato on VLAN 99 — free to repurpose or decommission
