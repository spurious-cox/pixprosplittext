#!/bin/zsh
# Build, sign and install PixProSplitText.app — v1.2.0
#
#   ./build.sh [--no-install]
#
# Installing is the default, as in every other project here.
#
# osacompile writes a bare applet: no CFBundleIdentifier, the stock applet
# icon, no version. All three are put back below, the same way
# PixProTransform's build does it, because codesign seals whatever it finds —
# with no identifier it seals the bundle NAME instead.
set -e
cd "${0:A:h}"

APP="PixProSplitText.app"
# Read from the script itself, so the bundle can never claim a version the
# code does not. Hard-coding it here once shipped an app reporting the
# previous release.
VERSION=$(/usr/bin/sed -n 's/^property scriptVersion : "\(.*\)"/\1/p' PixProSplitText.applescript)
[[ -n "$VERSION" ]] || { echo "error: no scriptVersion in PixProSplitText.applescript" >&2; exit 1; }
SIGN_ID="4208ABA3EC12F24C1F09C7BB624EFF68B44259DB"   # Developer ID Application

if ! security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "error: signing identity $SIGN_ID not in keychain" >&2
    exit 1
fi

echo "==> compiling $VERSION"
rm -rf "$APP"
osacompile -o "$APP" PixProSplitText.applescript

# osacompile does not compile anything: it COPIES Apple's applet stub off this
# machine, so the stub carries the minimum macOS of whatever system built it.
# Built on macOS 27, the app refuses to launch on 26 — and the script inside is
# just text, which would have run anywhere. The stub links only CoreServices
# and libSystem, so its recorded minimum is lowered to MIN_MACOS here.
MIN_MACOS=26.0
echo "==> setting the minimum macOS to $MIN_MACOS"
VTOOL=$(xcrun -f vtool 2>/dev/null)
if [[ -n "$VTOOL" ]]; then
    "$VTOOL" -set-build-version macos "$MIN_MACOS" "$MIN_MACOS" -replace \
        -output "$APP/Contents/MacOS/applet" "$APP/Contents/MacOS/applet" >/dev/null
    echo "    $(otool -l "$APP/Contents/MacOS/applet" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print "minos " $2; exit}')"
else
    echo "    vtool not found — the app will require the macOS it was built on" >&2
fi

echo "==> installing the icon"
# osacompile ships the stock applet icon, and writes an Assets.car whose
# CFBundleIconName WINS over CFBundleIconFile — so a custom icns can sit in
# the bundle and never be used. Both have to go.
cp PixProSplitText.icns "$APP/Contents/Resources/PixProSplitText.icns"
rm -f "$APP/Contents/Resources/applet.icns" "$APP/Contents/Resources/Assets.car"

echo "==> restoring bundle identity (osacompile drops it)"
/usr/bin/python3 - "$APP" "$VERSION" <<'PY'
import plistlib, sys
p = sys.argv[1] + "/Contents/Info.plist"
version = sys.argv[2]
d = plistlib.load(open(p, "rb"))
d.pop("CFBundleIconName", None)
d.update({
    "CFBundleName": "PixProSplitText",
    "CFBundleDisplayName": "PixProSplitText",
    "CFBundleIdentifier": "com.timmccoy.pixprosplittext",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "NSHumanReadableCopyright": "Copyright © 2026 Tim McCoy. All rights reserved.",
    "CFBundleGetInfoString": "PixProSplitText — split one text layer into any number of column layers.",
    "NSAppleEventsUsageDescription":
        "PixProSplitText splits a text layer into columns in Pixelmator Pro for you.",
    "CFBundleIconFile": "PixProSplitText",
})
plistlib.dump(d, open(p, "wb"))
PY

echo "==> signing with Developer ID"
codesign --force --deep --timestamp --options runtime \
    --entitlements "$HOME/My_Applications/_signing/pixpro-applet.entitlements" \
    --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"

if [[ "$1" == "--no-install" ]]; then
    echo "==> --no-install: built at $PWD/$APP"
    exit 0
fi

echo "==> installing to /Applications"
pkill -x PixProSplitText 2>/dev/null || true
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
xattr -dr com.apple.quarantine "/Applications/$APP" 2>/dev/null || true
codesign -dv "/Applications/$APP" 2>&1 | grep -E "Identifier=|Authority="
plutil -extract CFBundleShortVersionString raw "/Applications/$APP/Contents/Info.plist"
echo
echo "Not yet notarized. To notarize and staple:"
echo "  ~/My_Applications/_signing/pixpro_release.sh all /Applications/$APP"
