#!/usr/bin/env bash
# Spending Angel — assemble "Spending Angel.app" from a release build.
#
# Why a script and not an .xcodeproj: the app is a Swift Package (builds from
# the terminal and in Xcode, verifiable in CI), and a menu-bar app needs only
# a handful of Info.plist keys to become a real bundle — LSUIElement so there
# is no Dock icon, a bundle id so UserDefaults / launchd / os.log have a stable
# name, and the SwiftPM resource bundle next to the binary so Bundle.module
# resolves through Bundle.main.resourceURL. Ad-hoc signed (no Developer ID
# yet): runs locally and launchd accepts it; not notarised, so it will not
# pass Gatekeeper on another Mac.
#
# Safe to run while the app is running — it only writes under mac-app/.build.
# Output: mac-app/.build/Spending Angel.app. install.sh copies it into place.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/mac-app"
APP="$PKG/.build/Spending Angel.app"
BUNDLE_ID="net.modafoca.spendingangel"

# Single source of truth for the version: AppInfo.swift.
VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' "$PKG/Sources/SpendingAngel/AppInfo.swift" | head -n 1)"
if [ -z "$VERSION" ]; then
  echo "bundle: could not read AppInfo.version from $PKG/Sources/SpendingAngel/AppInfo.swift" >&2
  exit 1
fi

echo "bundle: building release v$VERSION"
swift build -c release --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)"
for needed in "$BIN/SpendingAngel" "$BIN/SpendingAngel_SpendingAngel.bundle"; do
  if [ ! -e "$needed" ]; then
    echo "bundle: release build did not produce $needed" >&2
    exit 1
  fi
done

echo "bundle: assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SpendingAngel" "$APP/Contents/MacOS/SpendingAngel"
cp -R "$BIN/SpendingAngel_SpendingAngel.bundle" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>Spending Angel</string>
	<key>CFBundleDisplayName</key>
	<string>Spending Angel</string>
	<key>CFBundleExecutable</key>
	<string>SpendingAngel</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"

# App icon from the sensor's 128 px mark, when the tools and the file exist.
# Upscaled sizes are soft but a real icon beats the generic one in Finder and
# the login-items list; skipped silently otherwise (the plist then has no
# CFBundleIconFile, which macOS handles fine).
ICON_SRC="$ROOT/extension/icons/icon128.png"
ICON_STATUS="skipped (no source or tools)"
if [ -f "$ICON_SRC" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$PKG/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  icon_ok=1
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1 || icon_ok=0
    sips -z "$((size * 2))" "$((size * 2))" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1 || icon_ok=0
  done
  if [ "$icon_ok" = 1 ] && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
    ICON_STATUS="AppIcon.icns from extension/icons/icon128.png"
  else
    ICON_STATUS="skipped (sips/iconutil failed)"
  fi
  rm -rf "$ICONSET"
fi

# The cast art comes out of Photoshop with Finder metadata (com.apple.FinderInfo)
# and cp keeps it; codesign refuses "resource fork, Finder information, or
# similar detritus" inside a bundle, so strip every extended attribute first.
echo "bundle: signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo
echo "bundle: done"
echo "  app:      $APP"
echo "  version:  $VERSION ($BUNDLE_ID)"
echo "  binary:   $BIN/SpendingAngel"
echo "  icon:     $ICON_STATUS"
echo "  next:     make install   (copies it to ~/Applications and starts it at login)"
