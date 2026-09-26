#!/usr/bin/env python3
"""Simulated Nanoleaf device for testing the plugin without real hardware.

Implements the parts of the Nanoleaf Open API the plugin uses (pairing, info,
state, effects, identify) and announces itself via mDNS with avahi-publish,
so it shows up in the panel's discovery like a real device.

Usage:
  tools/fake-nanoleaf.py                       # "Test Lines" on port 16030
  tools/fake-nanoleaf.py --name "Office Lines" --port 16031 --id FA:KE:00:00:00:02

State lives in memory only. Stop with Ctrl+C. The server listens on all
interfaces because mDNS announces the machine's LAN address; it controls
nothing real.
"""

import argparse
import json
import secrets
import shutil
import socketserver
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EFFECTS = ["Northern Lights", "Forest", "Sunset", "Ocean Waves", "Party"]


def make_state():
    return {
        "on": {"value": True},
        "brightness": {"value": 50, "max": 100, "min": 0},
        "hue": {"value": 0, "max": 360, "min": 0},
        "sat": {"value": 0, "max": 100, "min": 0},
        "ct": {"value": 4000, "max": 6500, "min": 1200},
        "colorMode": "effect",
    }


class Device:
    def __init__(self, name, device_id, model):
        self.name = name
        self.id = device_id
        self.model = model
        self.tokens = set()
        self.state = make_state()
        self.effect = EFFECTS[0]
        self.lock = threading.Lock()

    def info(self):
        return {
            "name": self.name,
            "serialNo": "FAKE" + self.id.replace(":", ""),
            "manufacturer": "Nanoleaf",
            "model": self.model,
            "firmwareVersion": "0.0.0-fake",
            "state": self.state,
            "effects": {"select": self.effect, "effectsList": EFFECTS},
        }

    def apply_state(self, body):
        s = self.state
        if "on" in body:
            s["on"]["value"] = bool(body["on"].get("value"))
        if "brightness" in body:
            s["brightness"]["value"] = max(0, min(100, int(body["brightness"].get("value", 0))))
            s["on"]["value"] = True
        if "hue" in body or "sat" in body:
            if "hue" in body:
                s["hue"]["value"] = max(0, min(360, int(body["hue"].get("value", 0))))
            if "sat" in body:
                s["sat"]["value"] = max(0, min(100, int(body["sat"].get("value", 0))))
            s["colorMode"] = "hs"
            self.effect = "*Solid*"
            s["on"]["value"] = True
        if "ct" in body:
            s["ct"]["value"] = max(1200, min(6500, int(body["ct"].get("value", 4000))))
            s["colorMode"] = "ct"
            self.effect = "*Solid*"
            s["on"]["value"] = True

    def select_effect(self, name):
        if name not in EFFECTS:
            return False
        self.effect = name
        self.state["colorMode"] = "effect"
        self.state["on"]["value"] = True
        return True


class Server(ThreadingHTTPServer):
    daemon_threads = True

    # HTTPServer.server_bind does a reverse DNS lookup (getfqdn) that can
    # stall startup for seconds; the name is not needed here.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def make_handler(device):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            sys.stderr.write("[%s] %s\n" % (device.name, fmt % args))

        def send_json(self, code, body=None):
            data = b"" if body is None else json.dumps(body).encode()
            self.send_response(code)
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def read_body(self):
            length = int(self.headers.get("Content-Length") or 0)
            if length == 0:
                return {}
            try:
                return json.loads(self.rfile.read(length))
            except ValueError:
                return None

        def route(self):
            parts = [p for p in self.path.split("/") if p]
            # /api/v1/<token>/<rest...>
            if len(parts) < 2 or parts[0] != "api" or parts[1] != "v1":
                return None, None
            if len(parts) == 2:
                return "", []
            return parts[2], parts[3:]

        def authorized(self, token):
            return token in device.tokens

        def do_POST(self):
            token, rest = self.route()
            if token == "new" and not rest:
                # A real device only pairs while its power button is held;
                # the fake always accepts.
                new = secrets.token_urlsafe(24)
                with device.lock:
                    device.tokens.add(new)
                return self.send_json(200, {"auth_token": new})
            self.send_json(404)

        def do_GET(self):
            token, rest = self.route()
            if token is None:
                return self.send_json(404)
            if not self.authorized(token):
                return self.send_json(401)
            if rest == []:
                with device.lock:
                    return self.send_json(200, device.info())
            self.send_json(404)

        def do_PUT(self):
            token, rest = self.route()
            if token is None:
                return self.send_json(404)
            if not self.authorized(token):
                return self.send_json(401)
            body = self.read_body()
            if body is None:
                return self.send_json(400)
            with device.lock:
                if rest == ["state"]:
                    device.apply_state(body)
                    return self.send_json(204)
                if rest == ["effects"] and "select" in body:
                    ok = device.select_effect(str(body["select"]))
                    return self.send_json(204 if ok else 400)
                if rest == ["identify"]:
                    sys.stderr.write("[%s] *blink blink*\n" % device.name)
                    return self.send_json(204)
            self.send_json(404)

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default="Test Lines")
    ap.add_argument("--port", type=int, default=16030)
    ap.add_argument("--id", default="FA:KE:00:00:00:01")
    ap.add_argument("--model", default="NL59")
    ap.add_argument("--no-mdns", action="store_true", help="do not announce via avahi (tests, CI)")
    args = ap.parse_args()

    device = Device(args.name, args.id, args.model)
    server = Server(("0.0.0.0", args.port), make_handler(device))

    publisher = None
    if args.no_mdns:
        pass
    elif shutil.which("avahi-publish"):
        publisher = subprocess.Popen([
            "avahi-publish", "-s", args.name, "_nanoleafapi._tcp", str(args.port),
            "id=" + args.id, "md=" + args.model, "srcvers=0.0.0-fake",
        ])
    else:
        sys.stderr.write("avahi-publish not found; the device will not show up in discovery.\n")

    sys.stderr.write("Fake Nanoleaf '%s' listening on port %d\n" % (args.name, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if publisher:
            publisher.terminate()


if __name__ == "__main__":
    main()
