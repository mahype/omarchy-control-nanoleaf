#!/usr/bin/env python3
"""End-to-end check of tools/fake-nanoleaf.py against the Open API calls the
plugin makes (pair, info, state, effects, identify)."""

import json
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAKE = ROOT / "tools" / "fake-nanoleaf.py"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class FakeDeviceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        cls.proc = subprocess.Popen(
            [sys.executable, str(FAKE), "--no-mdns", "--port", str(cls.port), "--name", "CI Lines"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        cls.addClassCleanup(cls.stop)
        cls.base = "http://127.0.0.1:%d/api/v1" % cls.port
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", cls.port), timeout=0.1).close()
                break
            except OSError:
                time.sleep(0.1)
        cls.token = cls.call("POST", "/new")[1]["auth_token"]

    @classmethod
    def stop(cls):
        cls.proc.terminate()
        cls.proc.wait(timeout=5)

    @classmethod
    def call(cls, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(cls.base + path, data=data, method=method)
        try:
            with urllib.request.urlopen(req, timeout=3) as r:
                raw = r.read()
                return r.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            return e.code, None

    def auth(self, path=""):
        return "/" + self.token + path

    def info(self):
        return self.call("GET", self.auth("/"))[1]

    def test_rejects_unknown_token(self):
        self.assertEqual(self.call("GET", "/nope/")[0], 401)

    def test_info_shape(self):
        info = self.info()
        self.assertEqual(info["name"], "CI Lines")
        self.assertIn("effectsList", info["effects"])
        self.assertIn("colorMode", info["state"])

    def test_modes_are_exclusive(self):
        self.assertEqual(self.call("PUT", self.auth("/state"), {"ct": {"value": 2700}})[0], 204)
        info = self.info()
        self.assertEqual((info["state"]["colorMode"], info["effects"]["select"]), ("ct", "*Solid*"))

        self.call("PUT", self.auth("/state"), {"hue": {"value": 200}, "sat": {"value": 80}})
        self.assertEqual(self.info()["state"]["colorMode"], "hs")

        self.assertEqual(self.call("PUT", self.auth("/effects"), {"select": "Forest"})[0], 204)
        info = self.info()
        self.assertEqual((info["state"]["colorMode"], info["effects"]["select"]), ("effect", "Forest"))

    def test_unknown_effect_is_rejected(self):
        self.assertEqual(self.call("PUT", self.auth("/effects"), {"select": "Nope"})[0], 400)

    def test_on_off_and_brightness(self):
        self.call("PUT", self.auth("/state"), {"on": {"value": False}})
        self.assertFalse(self.info()["state"]["on"]["value"])
        self.call("PUT", self.auth("/state"), {"brightness": {"value": 70, "duration": 0}})
        state = self.info()["state"]
        self.assertTrue(state["on"]["value"])
        self.assertEqual(state["brightness"]["value"], 70)

    def test_identify(self):
        self.assertEqual(self.call("PUT", self.auth("/identify"), {})[0], 204)


if __name__ == "__main__":
    unittest.main()
