#!/bin/bash
# Build Kopi.app: release build -> .app bundle -> codesign.
# Usage: scripts/build-app.sh [--install]   (--install copies to /Applications and launches)
#
# Signing: uses the local self-signed identity in ~/.kopi-signing (scripts/make-signing-identity.sh) so the
# designated requirement stays the same across rebuilds and macOS keeps the Accessibility grant (needed for
# direct paste). Falls back to ad-hoc (grant resets on every rebuild) when the identity is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Kopi"
APP="build/Kopi.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kopi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

KC="$HOME/.kopi-signing/kopi.keychain-db"
if [ -f "$KC" ]; then
  security unlock-keychain -p "$(cat "$HOME/.kopi-signing/pass")" "$KC"
  ID=$(security find-identity -p codesigning "$KC" | awk '/Kopi Local Signing/ {print $2; exit}')
  codesign --force --sign "$ID" --keychain "$KC" --identifier com.melvern.kopi "$APP"
else
  echo "warning: no local signing identity, using ad-hoc (Accessibility grant will reset)"
  codesign --force --sign - --identifier com.melvern.kopi "$APP"
fi
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Kopi || true
  sleep 1
  rm -rf /Applications/Kopi.app
  cp -R "$APP" /Applications/
  open /Applications/Kopi.app
  echo "installed /Applications/Kopi.app"
fi
