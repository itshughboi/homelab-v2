#!/usr/bin/env python3
"""Proxmox automated-install answer server (for `prepare-iso --fetch-from http`).

At install time the Proxmox auto-installer POSTs a JSON blob of the machine's
hardware (including NIC MACs) to this server. We match on MAC and return that
node's answer TOML — read straight from the repo, so changing a node's config
is just editing a file in git. No per-node ISOs to rebuild.

Stdlib only (no pip deps). Serves secrets (root hash, SSH keys) — keep it on the
management VLAN and only run it during provisioning. See README.md.
"""
import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ANSWERS_DIR = Path(os.environ.get("ANSWERS_DIR", "/answers"))
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8000"))

# MAC (lowercase, colon-separated) -> answer filename in ANSWERS_DIR.
# Same mapping you maintained in the old local.ipxe / MAC Reservations.
MAC_TO_NODE = {
    "04:7c:16:87:65:66": "pve-srv-1.toml",
    "c8:ff:bf:00:80:7c": "pve-srv-2.toml",
    "1c:83:41:40:ff:0b": "pve-srv-3.toml",
    "c8:ff:bf:03:f3:50": "pve-srv-4.toml",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("answers")


def macs_from_payload(info: dict) -> set[str]:
    """Pull MACs out of the installer's system-info JSON.

    NOTE: confirm the exact shape for your Proxmox version — run
    `proxmox-auto-install-assistant system-info` on a booted node, or read the
    raw payload this server logs on the first real request. This handles the
    common `network_interfaces: [{mac: ...}]` shape and a couple of fallbacks.
    """
    macs: set[str] = set()
    for n in info.get("network_interfaces", []) or []:
        mac = (n.get("mac") or n.get("address") or "").lower()
        if mac:
            macs.add(mac)
    # fallback: some versions nest under "network"
    for n in (info.get("network", {}) or {}).get("interfaces", []) or []:
        mac = (n.get("mac") or "").lower()
        if mac:
            macs.add(mac)
    return macs


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # simple health check
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            info = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            info = {}
        client = self.client_address[0]
        log.info("install request from %s; raw payload: %s", client,
                 raw.decode("utf-8", "replace"))

        macs = macs_from_payload(info)
        for mac, node in MAC_TO_NODE.items():
            if mac in macs:
                toml = (ANSWERS_DIR / node).read_bytes()
                log.info("matched %s via %s -> serving %s (%d bytes)",
                         client, mac, node, len(toml))
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(toml)))
                self.end_headers()
                self.wfile.write(toml)
                return

        log.warning("no answer matched %s; MACs seen: %s", client, sorted(macs))
        self.send_error(404, "no matching answer for this host")

    def log_message(self, *args):  # silence default access log; we log our own
        return


if __name__ == "__main__":
    if not ANSWERS_DIR.is_dir():
        raise SystemExit(f"ANSWERS_DIR {ANSWERS_DIR} not found")
    log.info("serving answers from %s on 0.0.0.0:%d", ANSWERS_DIR, LISTEN_PORT)
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
