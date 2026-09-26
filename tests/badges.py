#!/usr/bin/env python3
"""Writes shields.io endpoint JSON files from CI results.

Usage: tests/badges.py <results-dir> <out-dir>

<results-dir> holds:
  lcov.info     JS coverage (node --test lcov reporter)
  results.tap   JS test results (node --test tap reporter)
  python.txt    output of tests/test_fake_device.py
  qml.txt       output of tests/lint-qml.py
"""

import json
import os
import re
import sys


def badge(label, message, color):
    return {"schemaVersion": 1, "label": label, "message": message, "color": color}


def coverage(lcov):
    found = hit = 0
    for line in open(lcov):
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])
    return 100.0 * hit / found if found else 0.0


def js_counts(tap):
    text = open(tap).read()
    passed = re.search(r"^# pass (\d+)", text, re.M)
    failed = re.search(r"^# fail (\d+)", text, re.M)
    return int(passed.group(1)) if passed else 0, int(failed.group(1)) if failed else 0


def py_count(path):
    text = open(path).read()
    ran = re.search(r"Ran (\d+) tests?", text)
    ok = re.search(r"^OK\b", text, re.M)
    return (int(ran.group(1)) if ran else 0), bool(ok)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)

    pct = coverage(os.path.join(src, "lcov.info"))
    color = "brightgreen" if pct >= 90 else "green" if pct >= 80 else "yellow" if pct >= 60 else "red"
    badges = {"coverage": badge("coverage", "%d%%" % int(pct), color)}

    js_pass, js_fail = js_counts(os.path.join(src, "results.tap"))
    py_ran, py_ok = py_count(os.path.join(src, "python.txt"))
    failed = js_fail + (0 if py_ok else py_ran)
    total = js_pass + js_fail + py_ran
    badges["tests"] = badge("tests", "%d passed" % total if not failed else "%d failed" % failed,
                            "brightgreen" if not failed else "red")

    qml = open(os.path.join(src, "qml.txt")).read()
    m = re.search(r"(\d+) defect", qml)
    defects = int(m.group(1)) if m else -1
    badges["qml"] = badge("QML lint", "passing" if defects == 0 else "failing", "brightgreen" if defects == 0 else "red")

    badges["manifest"] = badge("manifest", "valid", "brightgreen")

    for name, data in badges.items():
        with open(os.path.join(out, name + ".json"), "w") as fh:
            json.dump(data, fh)
        print(name, data["message"])


if __name__ == "__main__":
    main()
