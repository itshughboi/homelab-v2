# Ventoy — Per-Node Auto-Install ISOs (rung A)

The zero-infrastructure automated path: bake each node's answer file into its own ISO, drop them
all on a Ventoy USB, boot the node, pick its ISO, walk away. No services to run.

Trade-off vs the [answer server](../proxmox-answer-server/README.md) (rung B): you rebuild a
node's ISO when its config changes, and you pick the node's ISO from the Ventoy menu (one
selection) rather than one generic ISO for all. For a small, rarely-reimaged cluster that's
fine; for heavy reimaging, rung B is nicer. Full comparison:
[provisioning/Ventoy.md](../../docs/2-proxmox/provisioning/Ventoy.md).

---

## Runbook — bringing up nodes end to end

> [!IMPORTANT] Validate, and canary one node first
> The only real risk is disk selection. The answer files use `[disk-setup]` with
> `filter.ID_TYPE = "disk"` — fine on a single-NVMe mini PC, but the kind of thing that either
> works perfectly or errors at install. **Validate every TOML, then test-boot ONE node and
> confirm it before building/booting the rest.** Catch a surprise once, not N times. (These
> install **ext4 on a single disk**, not ZFS — change `filesystem` if you want host-level ZFS
> snapshots.)
>
> [!WARNING] A validated TOML on one node doesn't mean the *schema* is proven
> A TOML that has never actually been run through `validate-answer` isn't evidence the schema is
> correct, even if the node it describes is up and running today (it may have been installed
> some other way — manually, or with a since-changed tool version). Don't assume an existing
> file is trustworthy just because its node exists; validate it for real before trusting the
> pattern for a new node.

### Answer file schema — confirmed correct as of `proxmox-auto-install-assistant` 9.2.7

The field names below are **not** what older examples/blog posts show, and in one case the
installed tool's own behavior contradicts the [upstream wiki](https://pve.proxmox.com/wiki/Automated_Installation).
Validated end-to-end producing a working ISO:

```toml
[global]
keyboard = "en-us"
country = "us"
fqdn = "pve-srv-2.hughboi.cc"        # required, and must be under [global] — NOT [network]
mailto = "root@hughboi.cc"            # required in practice on this tool version, despite the
                                       # upstream wiki listing it as optional
timezone = "America/Denver"
root-password = "$6$...hash..."       # kebab-case; root_password is deprecated
root-ssh-keys = [ "ssh-ed25519 ..." ] # kebab-case; ssh_public_keys is not a valid field at all
                                       # (hard parse error, not just a deprecation warning)

[network]
source = "from-answer"
cidr = "10.10.10.2/24"                # NOT "address"
dns = "9.9.9.9"                       # NOT "dns-list" (single string, not an array)
gateway = "10.10.10.254"
# no "hostname" field — fqdn in [global] covers it

[disk-setup]
filesystem = "ext4"
filter.ID_TYPE = "disk"
# disk-list and filter are mutually exclusive — do not set both.
# filter alone auto-selects "the disk" on a single-NVMe box.
```

Known-deprecated (warning, not fatal): `root_password`, `dns_list`, `disk_list` (underscore
style — kebab-case is preferred since PVE 8.4-1 / PBS 3.4-1).
Known-invalid (fatal parse error): `ssh_public_keys` — the real field is `root-ssh-keys`.

### 1. On pve-srv-1 — validate + build (amd64 tool lives here)

```sh
# repo + a current stock ISO on the host
git pull                                     # or git clone the repo
wget https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso

cd bootstrap/ventoy

# validate each answer file BEFORE building anything
for n in 2 3 4; do
  proxmox-auto-install-assistant validate-answer ./answers/pve-srv-$n.toml
done

# build per-node ISOs (make-isos.sh re-validates, then prepare-iso --fetch-from iso)
./make-isos.sh ~/proxmox-ve_9.2-1.iso
# → out/pve-srv-2-auto.iso, pve-srv-3-auto.iso, pve-srv-4-auto.iso
```

`make-isos.sh` loops every `pve-srv-*.toml` in `answers/` — including `pve-srv-1.toml`, which
will fail if it's never been fixed to the schema above. That's expected and harmless: pve-srv-1
is already installed, so its ISO is never needed. Re-run the script whenever a TOML changes.

> [!TIP] Getting the built ISOs onto the USB stick
> pve-srv-1 is headless — the ISOs land in `bootstrap/ventoy/out/` on that host, not on your
> Mac where the Ventoy stick is plugged in. Pull them over `scp` before copying to Ventoy:
>
> ```sh
> # on your Mac — quote the remote path, or your local shell will try (and fail) to
> # glob-expand pve-srv-*-auto.iso against your Mac's own filesystem
> scp "root@10.10.10.1:~/homelab/bootstrap/ventoy/out/pve-srv-*-auto.iso" ~/Downloads/proxmox-isos/
> ```

> [!IMPORTANT] The TOMLs contain root password **hashes** — and this repo is public
> `root_password` in each answer file is a SHA512-crypt hash. A public hash is offline-crackable
> if the source password is weak. Treat them as semi-public: **rotate the root password on every
> node right after install** (hardening playbook or `passwd`), and never put a weak/reused
> password through these files. Hashes already in git history are there permanently — rotation
> is the only real mitigation.

### 2. Make the Ventoy USB (one-time)

1. Flash **Ventoy** to the stick (formats it once).
2. Copy `out/pve-srv-*-auto.iso` onto the Ventoy partition. (Drop the plain stock ISO on too as
   a manual fallback — Ventoy holds many ISOs.)

BIOS per node: **USB boot first, Secure Boot off**.

### 3. Boot each node — srv-2 as the canary

1. Plug the node into **its permanent trunk port** on the Flex Mini (srv-2 → port 2, etc.,
   VLAN 10) — no cable move, the answer sets the static IP.
2. Boot from Ventoy → pick `pve-srv-2-auto.iso` → unattended install (~5–10 min) → reboots onto
   `10.10.10.2`.
3. **Verify before doing srv-3/4:**
   ```sh
   ssh root@10.10.10.2        # web UI: https://10.10.10.2:8006
   ```
   Clean? Repeat for srv-3 (`.3`) and srv-4 (`.4`). Disk misbehaved? Fix `[disk-setup]` in the
   TOMLs, rerun `make-isos.sh`, recopy — once.

### 4. Post-install handoff (per node)

The installer's job ends at "bootable Proxmox with the right IP." The rest is existing
automation:

1. **Network bridges/VLANs** — `ansible/playbooks/proxmox/network-setup/` creates `vmbr0.20`
   (Corosync) + `vmbr0.40` (storage). Run this **before** the cluster (Corosync needs VLAN 20).
2. **Form the cluster** — `pvecm create homelab` on pve-srv-1 (if not already), then
   `pvecm add 10.10.10.1` on each new node; confirm `pvecm status` shows quorum.
   Detail: [provisioning/README.md → Proxmox Cluster](../../docs/2-proxmox/provisioning/README.md#proxmox-cluster).
3. **Repos/updates** — `ansible/playbooks/proxmox/cluster-update/`.
4. **Then Terraform** provisions the k3s VMs onto srv-2/3/4.

## Optional — auto-boot (`ventoy.json`)

`ventoy.json` (copy to the USB root) sets a default ISO + menu aliases. Auto-boot picks **one**
default image, so it's most useful when you're **reimaging the same node repeatedly** during
testing — set that node's ISO as `VTOY_DEFAULT_IMAGE` and it boots with no keystrokes. For
mixed per-node installs you'll still pick from the menu.

> Confirm the `ventoy.json` key names / timeout option against the Ventoy control-plugin docs for
> your Ventoy version.
