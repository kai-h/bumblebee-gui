#!/bin/bash
# release.sh — build, sign, notarise, and package Bumblebee GUI as a DMG
#
# Prerequisites:
#   brew install create-dmg
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "app-specific-password"
#
# Usage:
#   cp .env.example .env   # then fill in your values
#   ./release.sh

set -euo pipefail

# Load signing config from .env (gitignored — copy .env.example to .env)
# shellcheck source=.env.example
source "$(dirname "$0")/.env"

SCHEME="BumblebeeGUI"
PROJECT="BumblebeeGUI.xcodeproj"
ARCHIVE="build/BumblebeeGUI.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/BumblebeeGUI.app"
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | awk '{print $3}' | tr -d ';')
DMG="build/BumblebeeGUI-$VERSION.dmg"

# ── Configuration (loaded from .env) ─────────────────────────────────────────
: "${TEAM_ID:?TEAM_ID not set — copy .env.example to .env and fill in your values}"
: "${SIGN_ID:?SIGN_ID not set — copy .env.example to .env and fill in your values}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE not set — copy .env.example to .env and fill in your values}"

echo "==> Cleaning build directory"
rm -rf build
mkdir -p build

echo "==> Signing bundled binaries"
codesign --force --options runtime \
  --sign "$SIGN_ID" \
  BumblebeeGUI/Resources/bumblebee_arm64 \
  BumblebeeGUI/Resources/bumblebee_x86_64

echo "==> Archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  CODE_SIGN_STYLE=Manual \
  | xcpretty 2>/dev/null || true

echo "==> Exporting"
cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$SIGN_ID</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions.plist \
  | xcpretty 2>/dev/null || true

echo "==> Notarising app"
ditto -c -k --keepParent "$APP" build/BumblebeeGUI.zip
xcrun notarytool submit build/BumblebeeGUI.zip \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP"

echo "==> Building DMG"
create-dmg \
  --volname "Bumblebee GUI" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "BumblebeeGUI.app" 140 190 \
  --app-drop-link 400 190 \
  --hide-extension "BumblebeeGUI.app" \
  "$DMG" \
  "$APP"

echo "==> Notarising DMG"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG"

echo ""
echo "Done: $DMG"

# ── Optional GitHub release ───────────────────────────────────────────────────
read -rp "Push to GitHub as release v$VERSION? [y/N] " PUSH_RELEASE
if [[ "$PUSH_RELEASE" == "y" || "$PUSH_RELEASE" == "Y" ]]; then
    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not found. Install with: brew install gh" >&2
        exit 1
    fi
    BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | awk '{print $3}' | tr -d ';')
    echo "==> Creating GitHub release v$VERSION (build $BUILD)"
    gh release create "v$VERSION" "$DMG" \
        --title "Bumblebee GUI v$VERSION" \
        --notes "Build $BUILD" \
        --latest
    echo "Released: $(gh release view "v$VERSION" --json url -q .url)"
fi
