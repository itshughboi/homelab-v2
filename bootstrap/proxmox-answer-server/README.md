# Proxmox Answer Server (HTTP auto-install)

Near-one-click node provisioning: **one** generic install ISO for every node, with each node's
answer file served dynamically by MAC. Change a node's config = edit its TOML in git; never
rebuild an ISO. This is "rung B" from [provisioning/Ventoy.md](../../docs/2-proxmox/provisioning/Ventoy.md)
— USB-booted (reliable), centrally-managed answers (the GitOps win netboot promised, without
netboot's fragility).

```
Ventoy USB (one generic ISO)
   └─ boot node → installer DHCPs a temp IP on VLAN 10
        └─ POST hardware info (MACs) → this server
             └─ server matches MAC → returns pve-srv-X.toml
                  └─ Proxmox installs unattended, applies static IP from the answer
```

---

## 1. Build the one ISO (on pve-srv-1 — amd64 tool)

```sh
proxmox-auto-install-assistant prepare-iso proxmox-ve_9.1-1.iso \
  --fetch-from http \
  --url http://10.10.10.10:8000/answer \
  --output pve-auto-http.iso
```

Drop `pve-auto-http.iso` on the Ventoy USB. That single ISO provisions every node.

> For HTTPS instead of plain HTTP, front this server with Traefik (`answers.hughboi.cc`) or use
> a self-signed cert and add `--cert-fingerprint <sha256>` to the command above — the installer
> pins it, so self-signed is safe. Plain HTTP on the management VLAN is fine for testing.

## 2. Run the server (where something is already up — e.g. dock-prod)

```sh
docker compose up -d        # start before a provisioning session
docker compose logs -f      # watch matches / payloads
docker compose down         # stop when done
```

It reads the per-node TOMLs from `../ventoy/answers/` (the canonical answer files)
and matches on MAC via the `MAC_TO_NODE` map in `answer_server.py`.

> [!IMPORTANT] Don't host it on a node you're installing
> The server must be reachable *during* the install, so run it on something already up
> (dock-prod / Athena / a k3s pod) — never the node currently being provisioned.

## 3. Confirm the payload schema (do this once)

The MAC matcher assumes the installer POSTs `network_interfaces: [{mac: ...}]`. **Verify the
real shape for your Proxmox version** before trusting it:

```sh
# on any booted Proxmox node — dumps the exact JSON the installer will POST
proxmox-auto-install-assistant system-info
```

Or just run a real install once and read the raw payload this server logs (`docker compose
logs`). If the keys differ, adjust `macs_from_payload()` in `answer_server.py`.

## 4. Test without a real install

```sh
# health
curl http://10.10.10.10:8000/healthz

# simulate the installer's POST for pve-srv-4
curl -X POST http://10.10.10.10:8000/answer \
  -H 'Content-Type: application/json' \
  -d '{"network_interfaces":[{"mac":"c8:ff:bf:03:f3:50"}]}'
# → should return pve-srv-4.toml
```

## 5. Boot a node

Plug into its **permanent trunk port** (VLAN 10) and boot the generic ISO from Ventoy. The
installer DHCPs a temp IP (VLAN 10 DHCP range), fetches its answer, then applies the **static**
IP from the TOML. No cable move. Traffic node→`10.10.10.10:8000` is intra-VLAN (MGMT→MGMT),
already allowed — no new firewall rule.

---

## Adding / changing a node

- **Change config:** edit `../ventoy/answers/pve-srv-X.toml`, commit. Nothing else.
- **Add a node:** drop a new `pve-srv-X.toml` + add one line to `MAC_TO_NODE` in
  `answer_server.py`. No ISO work.

## Security

The TOMLs contain the **root password hash + SSH keys** (already in the repo). Serving them over
HTTP means:
- Keep this on the **management VLAN only** (the bind in `compose.yaml` is `10.10.10.10:8000`).
- Prefer **HTTPS + `--cert-fingerprint`** for anything beyond a quick test.
- **Run it only during provisioning** (`restart: "no"`; `compose down` when finished).

## Optional — carry automation past install

Add a `[first-boot]` section to the TOMLs (PVE 8.3+) to run a script on first boot — e.g. have
the node trigger its own Ansible enrollment, so one boot goes bare-metal → installed → joining
the pipeline.

---

## Alternative: rung A (no server)

If you'd rather not run a service, the per-node baked-ISO approach (`make-isos.sh` + `ventoy.json`)
is in [../ventoy/](../ventoy/README.md). Trade-off: one ISO per node to rebuild on config change,
but zero infrastructure. Comparison table in [Ventoy.md](../../docs/2-proxmox/provisioning/Ventoy.md).
