#!/bin/bash
#
# Builds Mac Dial, signs it with a stable identity, installs it to /Applications and opens it.
#
# Why the signing step matters: macOS stores each privacy grant (Accessibility, Input
# Monitoring) against the app's designated requirement. An ad-hoc signature's requirement
# is its cdhash, which changes on every build, so each rebuild silently invalidates the
# grants while System Settings still shows the switch as on. Signing with an Apple
# Development certificate gives a requirement based on the bundle id and certificate,
# which stays the same across builds.
#
# Usage:
#   scripts/install-local.sh                      # build, sign, install, open
#   scripts/install-local.sh --reset-permissions  # also clear Mac Dial's stale privacy rows
#   MACDIAL_SIGN_IDENTITY="<name or SHA-1>" scripts/install-local.sh

set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.socuul.macdial"
APP_NAME="MacDial.app"
BUILT_APP="build/Build/Products/Release/$APP_NAME"
INSTALLED_APP="/Applications/$APP_NAME"
RESET_PERMISSIONS=0

for arg in "$@"; do
    case "$arg" in
        --reset-permissions) RESET_PERMISSIONS=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

identity="${MACDIAL_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | awk -F'"' '/"(Apple Development|Developer ID Application):/ { print $2; exit }')"
fi

echo "Building $APP_NAME"
xcodebuild -scheme MacDial -configuration Release \
    -derivedDataPath build -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
    build -quiet

if [ -n "$identity" ]; then
    echo "Signing with: $identity"
    codesign --force --deep --options runtime --timestamp=none --sign "$identity" "$BUILT_APP"
else
    echo "warning: no Apple Development certificate found. The app stays ad-hoc signed," >&2
    echo "warning: and you will need to grant permissions again after every rebuild." >&2
fi
codesign --verify --deep --strict "$BUILT_APP"
echo "Designated requirement: $(codesign -d -r- "$BUILT_APP" 2>&1 | sed -n 's/^designated => //p')"

echo "Quitting running copies"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x MacDial >/dev/null || break
    sleep 0.5
done
pkill -x MacDial 2>/dev/null || true

if [ "$RESET_PERMISSIONS" = 1 ]; then
    echo "Clearing Mac Dial's Accessibility and Input Monitoring rows"
    tccutil reset Accessibility "$BUNDLE_ID" || true
    tccutil reset ListenEvent "$BUNDLE_ID" || true
fi

echo "Installing to $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

open "$INSTALLED_APP"
echo "Done. Check that 'Dial' is in the menu bar."
