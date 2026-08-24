#!/usr/bin/env python3
"""Minimal HTTP health agent for the Necesse and playit source LXCs.

Reports healthy only when BOTH the service process is alive AND the UDP
socket is bound. Configure per-LXC via environment variables or CLI args:

    HEALTH_PORT      UDP port to check (default 14159)
    HEALTH_PROCESS   process name to match via pgrep (default "necesse")
    HEALTH_HTTP_PORT HTTP listen port (default 9101)
"""
import argparse
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer


def port_is_bound(port):
    out = subprocess.run(["ss", "-lun"], capture_output=True, text=True).stdout
    return f":{port} " in out or f":{port}\n" in out


def process_is_alive(name):
    out = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
    return out.returncode == 0


class Handler(BaseHTTPRequestHandler):
    port = 0
    process = ""

    def do_GET(self):
        if self.path != "/health":
            self.send_response(404)
            self.end_headers()
            return

        healthy = port_is_bound(self.port) and process_is_alive(self.process)
        body = json.dumps(
            {"healthy": healthy, "port": self.port, "process": self.process}
        ).encode()
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
    parser.add_argument("--listen", default="0.0.0.0")
    parser.add_argument(
        "--http-port",
        type=int,
        default=int(os.environ.get("HEALTH_HTTP_PORT", "9101")),
    )
    args = parser.parse_args()

    Handler.port = args.port
    Handler.process = args.process

    HTTPServer((args.listen, args.http_port), Handler).serve_forever()


if __name__ == "__main__":
    main()
