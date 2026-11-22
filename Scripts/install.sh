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

TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
fi

if [ -n "$TEAM" ]; then
    echo "==> Building MacBar, signed by team $TEAM"
    SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)
else
    echo "==> Building MacBar, signed ad hoc"
    SIGNING=(
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES
        CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
    )
fi

xcodebuild -project "$ROOT/MacBar.xcodeproj" -scheme MacBar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    ENABLE_HARDENED_RUNTIME=NO "${SIGNING[@]}" \
    | tail -5

APP="$DERIVED/Build/Products/Release/MacBar.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

if [ -z "$TEAM" ]; then
    # Re-sign nested XPC service and main bundle inside-out with ad-hoc signature
    if [ -d "$APP/Contents/XPCServices/MenuBarItemService.xpc" ]; then
        codesign --force --sign - "$APP/Contents/XPCServices/MenuBarItemService.xpc"
    fi
    codesign --force --sign - "$APP"
fi

echo "==> Verifying the signature before installing"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=' | sed 's/^/    /'

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
