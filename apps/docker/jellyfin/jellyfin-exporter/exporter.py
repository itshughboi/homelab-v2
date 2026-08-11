#!/usr/bin/env python3
"""
Minimal Jellyfin Prometheus exporter.

Polls the Jellyfin API (/Sessions, /System/Info, item counts) and exposes
playback/transcode/library metrics on :8080. Home-built (stdlib only) for the
same reason as the intel-gpu one: the third-party jellyfin-exporter images are
unvetted, and this needs a Jellyfin API key (a secret) — small auditable code is
preferable.

Config via env:
  JELLYFIN_URL      base URL (default http://jellyfin:8096)
  JELLYFIN_API_KEY  API key (required; created in Jellyfin: Dashboard > API Keys)
  POLL_SECONDS      how often to refresh (default 15)
"""
import json
import os
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = os.environ.get("JELLYFIN_URL", "http://jellyfin:8096").rstrip("/")
API_KEY = os.environ.get("JELLYFIN_API_KEY", "")
POLL = int(os.environ.get("POLL_SECONDS", "15"))
PORT = 8080

_metrics_text = "# jellyfin exporter starting\n"
_lock = threading.Lock()


def _get(path):
    req = urllib.request.Request(
        f"{BASE}{path}",
        headers={"Authorization": f'MediaBrowser Token="{API_KEY}"'},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


def _esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"')


def _collect():
    lines = []
    up = 0
    try:
        sessions = _get("/Sessions")
        up = 1

        active = [s for s in sessions if s.get("NowPlayingItem")]
        total_sessions = len(sessions)
        playing = len(active)

        transcoding = 0
        directplay = 0
        total_bitrate = 0
        by_user = {}
        by_client = {}
        for s in active:
            play = s.get("PlayState", {})
            method = "DirectPlay"
            ti = s.get("TranscodingInfo")
            if ti:
                # IsVideoDirect False => transcoding video
                if ti.get("IsVideoDirect") is False or ti.get("VideoCodec"):
                    method = "Transcode"
                total_bitrate += ti.get("Bitrate", 0) or 0
            if method == "Transcode":
                transcoding += 1
            else:
                directplay += 1
            u = s.get("UserName", "unknown")
            by_user[u] = by_user.get(u, 0) + 1
            c = s.get("Client", "unknown")
            by_client[c] = by_client.get(c, 0) + 1

        lines.append("# HELP jellyfin_sessions_total Current sessions (connected devices)")
        lines.append("# TYPE jellyfin_sessions_total gauge")
        lines.append(f"jellyfin_sessions_total {total_sessions}")

        lines.append("# HELP jellyfin_active_streams Sessions currently playing something")
        lines.append("# TYPE jellyfin_active_streams gauge")
        lines.append(f"jellyfin_active_streams {playing}")

        lines.append("# HELP jellyfin_streams_by_method Active streams by playback method")
        lines.append("# TYPE jellyfin_streams_by_method gauge")
        lines.append(f'jellyfin_streams_by_method{{method="transcode"}} {transcoding}')
        lines.append(f'jellyfin_streams_by_method{{method="directplay"}} {directplay}')

        lines.append("# HELP jellyfin_transcode_bitrate_bps Sum of transcode bitrates (bps)")
        lines.append("# TYPE jellyfin_transcode_bitrate_bps gauge")
        lines.append(f"jellyfin_transcode_bitrate_bps {total_bitrate}")

        if by_user:
            lines.append("# HELP jellyfin_active_streams_by_user Active streams per user")
            lines.append("# TYPE jellyfin_active_streams_by_user gauge")
            for u, n in by_user.items():
                lines.append(f'jellyfin_active_streams_by_user{{user="{_esc(u)}"}} {n}')
        if by_client:
            lines.append("# HELP jellyfin_active_streams_by_client Active streams per client app")
            lines.append("# TYPE jellyfin_active_streams_by_client gauge")
            for c, n in by_client.items():
                lines.append(f'jellyfin_active_streams_by_client{{client="{_esc(c)}"}} {n}')
    except Exception as e:
        lines.append(f"# scrape error: {_esc(e)}")

    # Library item counts (best-effort; separate try so a failure here doesn't zero sessions)
    try:
        counts = _get("/Items/Counts")
        lines.append("# HELP jellyfin_library_items Library item counts by type")
        lines.append("# TYPE jellyfin_library_items gauge")
        for k, v in counts.items():
            if isinstance(v, int):
                lines.append(f'jellyfin_library_items{{type="{_esc(k)}"}} {v}')
    except Exception:
        pass

    header = [
        "# HELP jellyfin_up 1 if the Jellyfin API responded",
        "# TYPE jellyfin_up gauge",
        f"jellyfin_up {up}",
    ]
    return "\n".join(header + lines) + "\n"


def _poller():
    global _metrics_text
    while True:
        text = _collect()
        with _lock:
            _metrics_text = text
        time.sleep(POLL)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/metrics", "/"):
            with _lock:
                body = _metrics_text.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


def main():
    if not API_KEY:
        print("WARNING: JELLYFIN_API_KEY not set — jellyfin_up will be 0")
    threading.Thread(target=_poller, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
