#!/usr/bin/env python3
"""Minimal HTTP health agent for the Necesse and playit source LXCs.

Two modes, selected via --mode / HEALTH_MODE:

  port_and_process (default) — for the Necesse LXC.
    Healthy only when BOTH the service process is alive AND the UDP
    socket is bound locally.
    Config: HEALTH_PORT (default 14159), HEALTH_PROCESS (default "necesse")

  playit — for the playit LXC.
    playit is an outbound tunnel client; it never binds the tunnel's
    port locally, so the port_and_process check is meaningless here.
    Instead this mode shells out to `playit status` (via sudo, since
    the status socket is root-owned) and reports healthy only when
    the reported Phase is "running".

Common config:
    HEALTH_HTTP_PORT   HTTP listen port (default 9101)
"""
import argparse
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

PLAYIT_BIN = "/usr/bin/playit"  # adjust if `which playit` differs

def port_is_bound(port):
    out = subprocess.run(["ss", "-lun"], capture_output=True, text=True).stdout
    return f":{port} " in out or f":{port}\n" in out


def process_is_alive(name):
    out = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
    return out.returncode == 0

def playit_is_running():
    """True only if `playit status` reports Phase: running."""
    try:
        result = subprocess.run(
            ["sudo", "-n", PLAYIT_BIN, "status"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False
    if result.returncode != 0:
        return False
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("Phase:"):
            return line.split(":", 1)[1].strip() == "running"
    return False

class Handler(BaseHTTPRequestHandler):
    port = 0
    process = ""
    mode = "port_and_process"  # "port_and_process" | "playit"

    def do_GET(self):
        if self.path != "/health":
            self.send_response(404)
            self.end_headers()
            return

        if self.mode == "playit":
            playit_ok = playit_is_running()
            healthy = playit_ok
            payload = {"healthy": healthy, "playit_phase_running": playit_ok}
        else:
            port_ok = port_is_bound(self.port)
            proc_ok = process_is_alive(self.process)
            healthy = port_ok and proc_ok
            payload = {
                "healthy": healthy,
                "port_ok": port_ok,
                "process_ok": proc_ok,
                "port": self.port,
                "process": self.process,
            }

        body = json.dumps(payload).encode()
        self.send_response(200 if healthy else 503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # quiet


def main():
    parser = argparse.ArgumentParser(description="Local health agent")
    parser.add_argument(
        "--port", type=int, default=int(os.environ.get("HEALTH_PORT", "14159"))
    )
    parser.add_argument(
        "--process", default=os.environ.get("HEALTH_PROCESS", "necesse")
    )
    parser.add_argument(
        "--mode",
        choices=["port_and_process", "playit"],
        default=os.environ.get("HEALTH_MODE", "port_and_process"),
    )
    parser.add_argument("--listen", default="0.0.0.0")
    parser.add_argument(
        "--http-port",
        type=int,
        default=int(os.environ.get("HEALTH_HTTP_PORT", "9101")),
    )
    args = parser.parse_args()
    Handler.port = args.port
    Handler.process = args.process
    Handler.mode = args.mode
    HTTPServer((args.listen, args.http_port), Handler).serve_forever()

if __name__ == "__main__":
    main()
