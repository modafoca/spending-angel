#!/usr/bin/env bash
# Spending Angel — install (or reinstall) the bundled app for this user.
#
# bundle.sh → ~/Applications/Spending Angel.app → a per-user LaunchAgent so it
# starts at login (RunAtLoad on, KeepAlive off, so "quit" in the dropdown
# sticks until the next login) → start it now → wait for `bridge.listening`
# in today's log. Idempotent: stops whatever copy is running, replaces the app
# and the plist, and re-bootstraps the agent. `--no-login-item` skips launchd
# and just opens the app once.
#
# Not for development sessions: it kills the running app, including a
# `swift run` debug copy. Use `make run` for that.
set -euo pipefail

usage() { echo "usage: scripts/install.sh [--no-login-item]"; }

LOGIN_ITEM=1
for arg in "$@"; do
  case "$arg" in
    --no-login-item) LOGIN_ITEM=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown option '$arg'" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="net.modafoca.spendingangel"
SRC="$ROOT/mac-app/.build/Spending Angel.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Spending Angel.app"
EXE="$DEST/Contents/MacOS/SpendingAngel"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
LOG="$HOME/Library/Logs/SpendingAngel/spending-angel-$(date +%Y-%m-%d).jsonl"
UID_NUM="$(id -u)"

"$ROOT/scripts/bundle.sh"

echo "install: stopping any running copy"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
pkill -x SpendingAngel 2>/dev/null || true
sleep 1

echo "install: copying to $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"

# Lines already in today's log belong to earlier runs (a debug copy, say);
# only a bridge.listening written after this point counts as this launch.
BEFORE=0
if [ -f "$LOG" ]; then BEFORE="$(wc -l < "$LOG" | tr -d ' ')"; fi

if [ "$LOGIN_ITEM" = 1 ]; then
  echo "install: registering LaunchAgent $LABEL (starts at login)"
  mkdir -p "$AGENTS"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$EXE</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
  plutil -lint -s "$PLIST"
  launchctl bootstrap "gui/$UID_NUM" "$PLIST"
else
  echo "install: --no-login-item — opening the app once, no LaunchAgent"
  rm -f "$PLIST"
  open "$DEST"
fi

echo "install: waiting for the bridge (up to 5 s)"
for _ in $(seq 1 25); do
  if [ -f "$LOG" ] && tail -n +"$((BEFORE + 1))" "$LOG" | grep -q '"event":"bridge.listening"'; then
    echo
    echo "install: Spending Angel v$VERSION is running — bridge listening on 127.0.0.1:17865"
    echo "  app:    $DEST"
    if [ "$LOGIN_ITEM" = 1 ]; then echo "  login:  $PLIST"; else echo "  login:  not registered (--no-login-item)"; fi
    echo "  log:    $LOG"
    echo "  next:   in Chrome, open the extension's Settings; it shows the last connection after the next"
    echo "          catch (Test connection works). Updated the extension too? Reload it at chrome://extensions."
    exit 0
  fi
  sleep 0.2
done

echo
echo "install: Spending Angel v$VERSION is in place but no bridge.listening appeared within 5 s." >&2
echo "  Check the menu bar for the \$-halo icon and today's log: $LOG" >&2
exit 1
