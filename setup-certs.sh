#!/bin/bash
# setup-certs.sh — import Developer ID signing certificates into the keychain
#
# Use this to set up signing on a new machine. Export .p12 files from
# Keychain Access on an existing machine:
#   Right-click "Developer ID Application: ..." → Export → .p12
#   Right-click "Developer ID Installer: ..."   → Export → .p12
#
# Usage (interactive):
#   ./setup-certs.sh --app DevIDApp.p12 --installer DevIDInstaller.p12
#   ./setup-certs.sh --app DevIDApp.p12                 # app cert only
#   ./setup-certs.sh --installer DevIDInstaller.p12     # installer cert only
#
# Usage (CI — supply passwords via env vars to skip prompts):
#   APP_P12_PASSWORD=secret \
#   INSTALLER_P12_PASSWORD=secret \
#   KEYCHAIN_PASSWORD=secret \
#   ./setup-certs.sh --app DevIDApp.p12 --installer DevIDInstaller.p12
#
# After running, set up the notarytool profile expected by release.sh:
#   xcrun notarytool store-credentials "NotaryProfile" \
#     --apple-id "$APPLE_ID" \
#     --team-id "S5B5YSJ6Q3" \
#     --password "<app-specific-password>"

set -euo pipefail

# Pull TEAM_ID, SIGN_ID, NOTARY_PROFILE from .env if present
ENV_FILE="$(dirname "$0")/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

APP_P12=""
INSTALLER_P12=""

usage() {
    echo "Usage: $0 [--app <app.p12>] [--installer <installer.p12>]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)       APP_P12="$2";       shift 2 ;;
        --installer) INSTALLER_P12="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

[[ -z "$APP_P12" && -z "$INSTALLER_P12" ]] && usage

KEYCHAIN=$(security default-keychain -d user | xargs)

prompt_password() {
    local prompt="$1"
    local var="$2"
    local val="${!var:-}"
    if [[ -z "$val" ]]; then
        read -r -s -p "$prompt — press Enter if none: " val
        echo
    fi
    echo "$val"
}

import_p12() {
    local p12="$1"
    local label="$2"
    local pass_var="$3"

    [[ ! -f "$p12" ]] && { echo "Error: file not found: $p12" >&2; exit 1; }

    local pass
    pass=$(prompt_password "Password for $label ($(basename "$p12"))" "$pass_var")

    echo "==> Importing $label"
    security import "$p12" \
        -k "$KEYCHAIN" \
        -P "$pass" \
        -T /usr/bin/codesign \
        -T /usr/bin/productbuild \
        -T /usr/bin/security
    echo "    Done."
}

[[ -n "$APP_P12" ]]       && import_p12 "$APP_P12"       "Developer ID Application" "APP_P12_PASSWORD"
[[ -n "$INSTALLER_P12" ]] && import_p12 "$INSTALLER_P12" "Developer ID Installer"   "INSTALLER_P12_PASSWORD"

# Grant codesign/productbuild silent access to the imported private keys.
# This prevents "allow access" dialogs during builds.
echo "==> Setting key partition list on $KEYCHAIN"
KEYCHAIN_PASS=$(prompt_password "Login keychain password (needed to grant key access)" "KEYCHAIN_PASSWORD")
security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s -k "$KEYCHAIN_PASS" \
    "$KEYCHAIN" 2>/dev/null || true
echo "    Done."

echo ""
echo "==> Verifying"
printf "  Application: "
security find-identity -v -p codesigning | grep "Developer ID Application" \
    | sed 's/.*"\(.*\)"/\1/' || echo "(not found — check the .p12 contains the private key)"
printf "  Installer:   "
security find-identity -v | grep "Developer ID Installer" \
    | sed 's/.*"\(.*\)"/\1/' || echo "(not found — check the .p12 contains the private key)"

echo ""
echo "Certificate names above must match SIGN_ID in .env:"
echo "  Expected: ${SIGN_ID:-(SIGN_ID not set in .env)}"
echo ""
echo "If the notarytool profile is not yet set up, run:"
echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE:-NotaryProfile}\" \\"
echo "    --apple-id \"${APPLE_ID:-you@example.com}\" \\"
echo "    --team-id \"${TEAM_ID:-XXXXXXXXXX}\" \\"
echo "    --password \"<app-specific-password>\""
