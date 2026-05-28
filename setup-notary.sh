#!/bin/bash
# setup-notary.sh — store notarytool credentials in the login keychain
#
# Reads APPLE_ID, TEAM_ID, and NOTARY_PROFILE from .env, then prompts
# for an app-specific password (generate one at appleid.apple.com →
# Sign-In and Security → App-Specific Passwords).
#
# Usage:
#   ./setup-notary.sh

set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: .env not found. Copy .env.example to .env and fill in your values." >&2
    exit 1
fi
source "$ENV_FILE"

: "${APPLE_ID:?APPLE_ID not set in .env}"
: "${TEAM_ID:?TEAM_ID not set in .env}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE not set in .env}"

echo "Storing notarytool credentials"
echo "  Profile : $NOTARY_PROFILE"
echo "  Apple ID: $APPLE_ID"
echo "  Team ID : $TEAM_ID"
echo ""
echo "Generate an app-specific password at appleid.apple.com if you don't have one."
echo ""

read -r -s -p "App-specific password: " APP_PASSWORD
echo ""

xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"

echo ""
echo "Done. Credentials stored as '$NOTARY_PROFILE' in the login keychain."
