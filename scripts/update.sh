#!/usr/bin/env bash
# Spending Angel — pull the latest commits and reinstall the app.
#
# The extension is loaded unpacked from this checkout, so a pull updates its
# files in place — but Chrome only picks them up after a reload. When anything
# under extension/ changed between the old and new HEAD this ends with a loud
# reminder. Flags (`--no-login-item`) pass straight through to install.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BEFORE="$(git rev-parse HEAD)"
echo "update: git pull --ff-only (from $(git rev-parse --short "$BEFORE"))"
git pull --ff-only
AFTER="$(git rev-parse HEAD)"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "update: already at $(git rev-parse --short "$AFTER") — reinstalling anyway"
else
  echo "update: now at $(git rev-parse --short "$AFTER")"
fi

status=0
"$ROOT/scripts/install.sh" "$@" || status=$?

if [ -n "$(git diff --name-only "$BEFORE" "$AFTER" -- extension/)" ]; then
  echo
  echo "=============================================================================="
  echo "  THE EXTENSION CHANGED — RELOAD IT:"
  echo "  chrome://extensions → \"Spending Angel — Sensor\" → the reload (↻) button."
  echo "  Until then the sensor runs the old code and its version hint stays stale."
  echo "=============================================================================="
fi

exit "$status"
