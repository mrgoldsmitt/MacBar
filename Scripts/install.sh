#!/bin/bash
#
# Builds MacBar and installs it, signed.
#
# Installs to /Applications by default. Override DEST=$HOME/Applications if needed.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-/Applications}"
DERIVED="${DERIVED:-/tmp/macbar-build}"

resolve_signing_identity() {
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        echo "$SIGN_IDENTITY"
        return
    fi
    local valid_apple
    valid_apple="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E 'Developer ID Application|Apple Development' \
        | awk '{print $2}' | head -n 1 || true)"
    if [ -n "$valid_apple" ]; then
        echo "$valid_apple"
        return
    fi
    local local_cert
    local_cert="$(security find-identity -p codesigning 2>/dev/null \
        | grep 'MacBar Local Code Signing' \
        | awk '{print $2}' | head -n 1 || true)"
    if [ -n "$local_cert" ]; then
        echo "$local_cert"
        return
    fi
    echo "-"
}

SIGN_ID="$(resolve_signing_identity)"
echo "==> Building MacBar (signing identity: $SIGN_ID)"

xcodebuild -project "$ROOT/MacBar.xcodeproj" -scheme MacBar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    ENABLE_HARDENED_RUNTIME=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    | tail -5

APP="$DERIVED/Build/Products/Release/MacBar.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

SIGN_ARGS=(--force --sign "$SIGN_ID")
if [ "$SIGN_ID" != "-" ]; then
    SIGN_ARGS+=(--timestamp=none)
fi

if [ -d "$APP/Contents/XPCServices/MenuBarItemService.xpc" ]; then
    codesign "${SIGN_ARGS[@]}" "$APP/Contents/XPCServices/MenuBarItemService.xpc"
fi
codesign "${SIGN_ARGS[@]}" "$APP"

echo "==> Verifying the signature before installing"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Authority=' | sed 's/^/    /'
codesign -dr - "$APP" 2>&1 | grep 'designated' | sed 's/^/    /'

echo "==> Installing to $DEST"
if pgrep -x MacBar >/dev/null 2>&1; then
    osascript -e 'quit app "MacBar"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x MacBar >/dev/null 2>&1 || break
        sleep 0.3
    done
    pgrep -x MacBar >/dev/null 2>&1 && pkill -x MacBar || true
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/MacBar.app"
ditto "$APP" "$DEST/MacBar.app"
xattr -cr "$DEST/MacBar.app" || true

echo "==> Verifying the installed copy"
codesign --verify --deep --strict "$DEST/MacBar.app"

open -a "$DEST/MacBar.app"
echo "==> Running from $DEST/MacBar.app"
