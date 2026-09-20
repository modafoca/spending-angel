#!/usr/bin/env bash
# Spending Angel — remove the installed app and its login item.
#
# Stops the app, removes the LaunchAgent plist and ~/Applications/Spending
# Angel.app. Settings (UserDefaults under net.modafoca.spendingangel — goal,
# character, counter, pairing token) and logs are kept unless `--purge` is
# given, so a reinstall picks up where you left off. Purge also removes the
# legacy development app's settings so migration cannot restore them later.
# Idempotent: safe to run when nothing is installed.
set -euo pipefail

usage() { echo "usage: scripts/uninstall.sh [--purge]"; }

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall: unknown option '$arg'" >&2; usage >&2; exit 2 ;;
  esac
done

LABEL="net.modafoca.spendingangel"
DEST="$HOME/Applications/Spending Angel.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/SpendingAngel"

echo "uninstall: stopping the app"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x SpendingAngel 2>/dev/null || true

if [ -f "$PLIST" ]; then rm -f "$PLIST"; echo "uninstall: removed $PLIST"; else echo "uninstall: no LaunchAgent to remove"; fi
if [ -d "$DEST" ]; then rm -rf "$DEST"; echo "uninstall: removed $DEST"; else echo "uninstall: no app in ~/Applications"; fi

if [ "$PURGE" = 1 ]; then
  # First launch imports SpendingAngel into the bundle's defaults domain.
  # Erase both on explicit purge, otherwise reinstall resurrects the old
  # goal and pairing token after the migration marker has been deleted.
  for domain in "$LABEL" SpendingAngel; do
    if defaults read "$domain" >/dev/null 2>&1; then
      defaults delete "$domain"
      echo "uninstall: removed settings ($domain)"
    else
      echo "uninstall: no settings to remove ($domain)"
    fi
  done
  if [ -d "$LOGS" ]; then rm -rf "$LOGS"; echo "uninstall: removed $LOGS"; else echo "uninstall: no logs to remove"; fi
else
  echo "uninstall: settings and logs kept (re-run with --purge to remove them)"
fi

echo
echo "uninstall: done"
echo "  next:  the Chrome extension is separate — remove it at chrome://extensions if you are done with it."
