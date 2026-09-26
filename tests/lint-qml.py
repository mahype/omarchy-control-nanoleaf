#!/usr/bin/env python3
"""Runs qmllint on the plugin's QML and fails on real defects only.

Omarchy's own modules (qs.Commons, qs.Ui) and Quickshell are not available in
CI, so import/unqualified/unresolved warnings are expected noise. Defects that
qmllint can still see through Qt's own types -- e.g. a property or id that
shadows a built-in like Item.palette -- fail the check.

Usage: tests/lint-qml.py [files...]   (default: all *.qml in the repo root)
Exit code 0 = clean, 1 = defects found, 2 = qmllint missing.
"""

import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAIL_IDS = {
    "property-override",
    "missing-property",
    "duplicate-property-binding",
    "duplicated-name",
    "read-only-property",
    "incompatible-type",
    "alias-cycle",
    "syntax",
    "deprecated",
}


def find_qmllint():
    for c in ("qmllint6", "qmllint", "/usr/lib/qt6/bin/qmllint"):
        p = shutil.which(c) or (c if os.path.isfile(c) else None)
        if p:
            return p
    return None


def is_noise(w):
    # Members looked up on an unresolved (Omarchy/Quickshell) object degrade
    # to QObject; those lookups are not meaningful without the real modules.
    return w.get("id") == "missing-property" and 'type "QObject"' in w.get("message", "")


def main():
    qmllint = find_qmllint()
    if not qmllint:
        print("qmllint not found", file=sys.stderr)
        return 2
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "*.qml")))
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "lint.json")
        subprocess.run([qmllint, "--json", out, *files], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(out) as fh:
            report = json.load(fh)

    defects = []
    for f in report.get("files", []):
        name = os.path.relpath(f.get("filename", "?"), ROOT)
        if not f.get("success", True) and not f.get("warnings"):
            defects.append("%s: qmllint failed to process the file" % name)
        for w in f.get("warnings", []):
            if w.get("type") == "critical" or (w.get("id") in FAIL_IDS and not is_noise(w)):
                defects.append("%s:%s:%s: %s [%s]" % (name, w.get("line"), w.get("column"), w.get("message"), w.get("id")))

    for d in defects:
        print(d)
    print("qml lint: %d file(s), %d defect(s)" % (len(files), len(defects)))
    return 1 if defects else 0


if __name__ == "__main__":
    sys.exit(main())
