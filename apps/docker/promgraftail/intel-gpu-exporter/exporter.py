#!/usr/bin/env python3
"""
Minimal Intel GPU Prometheus exporter.

Runs `intel_gpu_top -J` as a long-lived subprocess (which streams a JSON array of
per-interval samples) and exposes the latest sample as Prometheus metrics on :8080.

Why home-built: the well-known intel-gpu-exporter images are archived/unmaintained
or unvetted, and this runs privileged with /dev/dri + host PID — small auditable
code is safer than trusting a stranger's image. Parses only the fields the A380
actually emits (engines, frequency, rc6, interrupts); power/imc are absent on this
discrete Arc via i915, so they're simply skipped if not present.
"""
import json
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INTERVAL_MS = 2000          # intel_gpu_top sampling period
PORT = 8080

# Latest parsed sample, guarded by a lock. Starts empty until the first reading.
_latest = {}
_lock = threading.Lock()
_last_update = 0.0


def _reader():
    """Continuously read intel_gpu_top -J and keep the newest sample."""
    global _latest, _last_update
    while True:
        try:
            proc = subprocess.Popen(
                ["intel_gpu_top", "-J", "-s", str(INTERVAL_MS)],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            )
            buf = ""
            depth = 0
            started = False
            # intel_gpu_top emits "[\n {..},\n {..},\n ..." — stream balanced objects.
            for ch in iter(lambda: proc.stdout.read(1), ""):
                if ch == "{":
                    depth += 1
                    started = True
                if started:
                    buf += ch
                if ch == "}":
                    depth -= 1
                    if depth == 0 and started:
                        try:
                            obj = json.loads(buf)
                            with _lock:
                                _latest = obj
                                _last_update = time.time()
                        except json.JSONDecodeError:
                            pass
                        buf = ""
                        started = False
            proc.wait()
        except FileNotFoundError:
            # intel_gpu_top missing — sleep and retry so the container doesn't crashloop.
            time.sleep(10)
        except Exception:
            time.sleep(5)


def _sanitize(name):
    return name.replace("/", "_").replace("-", "_").replace(" ", "_").lower()


def _render():
    """Render the latest sample as Prometheus exposition text."""
    with _lock:
        d = dict(_latest)
        age = time.time() - _last_update if _last_update else -1

    lines = []
    lines.append("# HELP intel_gpu_up 1 if a recent intel_gpu_top sample was read")
    lines.append("# TYPE intel_gpu_up gauge")
    up = 1 if (0 <= age < 30) else 0
    lines.append(f"intel_gpu_up {up}")

    if not d:
        return "\n".join(lines) + "\n"

    freq = d.get("frequency", {})
    if "actual" in freq:
        lines.append("# HELP intel_gpu_frequency_mhz GPU clock frequency in MHz")
        lines.append("# TYPE intel_gpu_frequency_mhz gauge")
        lines.append(f'intel_gpu_frequency_mhz{{type="actual"}} {freq.get("actual",0)}')
        lines.append(f'intel_gpu_frequency_mhz{{type="requested"}} {freq.get("requested",0)}')

    rc6 = d.get("rc6", {})
    if "value" in rc6:
        lines.append("# HELP intel_gpu_rc6_percent RC6 power-saving residency percent")
        lines.append("# TYPE intel_gpu_rc6_percent gauge")
        lines.append(f'intel_gpu_rc6_percent {rc6.get("value",0)}')

    irq = d.get("interrupts", {})
    if "count" in irq:
        lines.append("# HELP intel_gpu_interrupts_per_second GPU interrupts per second")
        lines.append("# TYPE intel_gpu_interrupts_per_second gauge")
        lines.append(f'intel_gpu_interrupts_per_second {irq.get("count",0)}')

    engines = d.get("engines", {})
    if engines:
        lines.append("# HELP intel_gpu_engine_busy_percent Per-engine busy percent")
        lines.append("# TYPE intel_gpu_engine_busy_percent gauge")
        for name, vals in engines.items():
            eng = _sanitize(name)
            busy = vals.get("busy", 0)
            lines.append(f'intel_gpu_engine_busy_percent{{engine="{name}",engine_id="{eng}"}} {busy}')

    clients = d.get("clients", {})
    if isinstance(clients, dict):
        lines.append("# HELP intel_gpu_clients Number of GPU clients (processes) active")
        lines.append("# TYPE intel_gpu_clients gauge")
        lines.append(f"intel_gpu_clients {len(clients)}")

    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/metrics", "/"):
            body = _render().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass  # quiet


def main():
    t = threading.Thread(target=_reader, daemon=True)
    t.start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
