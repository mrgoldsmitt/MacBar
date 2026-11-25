#!/bin/bash
#
# Builds MacBar.app in Release mode and packages a native macOS DMG in dist/MacBar.dmg.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/macbar-build}"
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/MacBar.dmg"
RW_DMG="/tmp/MacBar-rw.dmg"
STAGE_DIR="/tmp/MacBar-dmg-stage"
MOUNT_DIR="/Volumes/MacBar"

cleanup() {
    if mount | grep -q "on $MOUNT_DIR "; then
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGE_DIR" "$RW_DMG"
}
trap cleanup EXIT

cleanup

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
echo "==> Building MacBar (Release, signing identity: $SIGN_ID)"

xcodebuild -project "$ROOT/MacBar.xcodeproj" -scheme MacBar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    ENABLE_HARDENED_RUNTIME=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    | tail -10

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

echo "==> Verifying app bundle signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dr - "$APP" 2>&1 | sed 's/^/    /'

echo "==> Staging DMG contents"
mkdir -p "$DIST_DIR" "$STAGE_DIR/.background"
ditto "$APP" "$STAGE_DIR/MacBar.app"
ln -s /Applications "$STAGE_DIR/Applications"

# Generate clean dark-glass DMG background image
swift - <<'SWIFT' "$STAGE_DIR/.background/bg.png"
import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments[1]
let width = 620
let height = 380
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let cs = CGColorSpaceCreateDeviceRGB()
let colors = [
    NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.22, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.14, alpha: 1.0).cgColor,
] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
}

// Subtle directional arrow between MacBar.app (x=175) and Applications (x=445)
let yCenter: CGFloat = 195
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 278, y: yCenter))
arrow.line(to: CGPoint(x: 342, y: yCenter))
arrow.move(to: CGPoint(x: 330, y: yCenter + 10))
arrow.line(to: CGPoint(x: 342, y: yCenter))
arrow.line(to: CGPoint(x: 330, y: yCenter - 10))
arrow.lineWidth = 3.0
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.55, green: 0.78, blue: 1.0, alpha: 0.55).setStroke()
arrow.stroke()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.65),
]
let caption = "Drag MacBar into Applications" as NSString
let textSize = caption.size(withAttributes: attrs)
caption.draw(at: CGPoint(x: (CGFloat(width) - textSize.width) / 2, y: 42), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
SWIFT

# Copy app icns as volume icon if compiled into the app bundle
ICNS_PATH="$(find "$APP/Contents/Resources" -name "*.icns" | head -n 1 || true)"
if [ -n "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$STAGE_DIR/.VolumeIcon.icns"
fi

echo "==> Creating read-write DMG"
rm -f "$RW_DMG" "$DMG_PATH"
hdiutil create -volname "MacBar" -srcfolder "$STAGE_DIR" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null

echo "==> Configuring DMG Finder layout"
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEV_NODE="$(echo "$ATTACH_OUT" | awk '/\/Volumes\/MacBar/ {print $1; exit}')"

if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT_DIR" || true
fi

# Apply Finder view layout with graceful timeout fallback
(
    osascript <<'OSA'
tell application "Finder"
    tell disk "MacBar"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {260, 180, 880, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set background picture of viewOptions to file ".background:bg.png"
        set position of item "MacBar.app" of container window to {175, 185}
        set position of item "Applications" of container window to {445, 185}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
) >/dev/null 2>&1 || echo "Note: Finder layout customization skipped (non-interactive fallback)"

sync
hdiutil detach "$DEV_NODE" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true

echo "==> Compressing final DMG to $DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

if [ "$SIGN_ID" != "-" ]; then
    echo "==> Signing DMG with $SIGN_ID"
    codesign "${SIGN_ARGS[@]}" "$DMG_PATH"
fi

echo "==> Verifying DMG integrity and embedded app signature"
hdiutil verify "$DMG_PATH"
VERIFY_OUT="$(hdiutil attach -readonly -noverify -nobrowse "$DMG_PATH")"
VERIFY_DEV="$(echo "$VERIFY_OUT" | awk '/\/Volumes\/MacBar/ {print $1; exit}')"
codesign --verify --deep --strict "$MOUNT_DIR/MacBar.app"
hdiutil detach "$VERIFY_DEV" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true

ls -lh "$DMG_PATH"
echo "==> Done: $DMG_PATH"
