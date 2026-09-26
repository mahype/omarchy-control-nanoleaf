#!/bin/bash
# Runs every check CI runs. Results land in ./test-results (lcov, tap, logs).
# QML lint is skipped with a notice when qmllint is not installed.

set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-results

echo "== manifest"
bash tests/check-manifest.sh

echo "== JavaScript tests + coverage"
node --test \
  --experimental-test-coverage \
  --test-coverage-exclude='tests/**' \
  --test-coverage-lines=95 --test-coverage-functions=95 --test-coverage-branches=80 \
  --test-reporter=spec --test-reporter-destination=stdout \
  --test-reporter=lcov --test-reporter-destination=test-results/lcov.info \
  --test-reporter=tap --test-reporter-destination=test-results/results.tap \
  tests/*.test.js

echo "== fake device"
python3 tests/test_fake_device.py 2>&1 | tee test-results/python.txt
grep -q '^OK' test-results/python.txt

echo "== QML lint"
if python3 tests/lint-qml.py | tee test-results/qml.txt; then
  # The linter must also reject a known-bad file, or the check proves nothing.
  if python3 tests/lint-qml.py tests/fixtures/ShadowedPalette.qml >/dev/null; then
    echo "QML lint did not catch tests/fixtures/ShadowedPalette.qml" >&2
    exit 1
  fi
else
  rc=$?
  [[ $rc -eq 2 ]] && echo "qmllint not installed, skipped" || exit $rc
fi

echo "== all checks passed"
