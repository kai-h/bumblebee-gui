#!/usr/bin/env bash
# Downloads the latest bumblebee release binaries and threat_intel into the Xcode project.
# Run this once before building, and re-run to update to a newer release.
set -euo pipefail

RESOURCES_DIR="$(dirname "$0")/BumblebeeGUI/Resources"

echo "Fetching latest release info from GitHub…"
RELEASE_JSON=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/perplexityai/bumblebee/releases/latest")

VERSION=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest release: $VERSION"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

download_and_extract() {
  local ARCH_LABEL=$1   # arm64 or x86_64
  local ASSET_ARCH=$2   # arm64 or amd64 (GitHub asset naming)

  ASSET_URL=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
match = next((a['browser_download_url'] for a in assets
              if 'darwin' in a['name'] and '$ASSET_ARCH' in a['name'] and a['name'].endswith('.tar.gz')), None)
print(match or '')
")

  if [ -z "$ASSET_URL" ]; then
    echo "  [!] No darwin/$ASSET_ARCH asset found — skipping $ARCH_LABEL"
    return
  fi

  echo "  Downloading $ARCH_LABEL binary…"
  TARBALL="$TMPDIR_WORK/bumblebee_$ARCH_LABEL.tar.gz"
  curl -fsSL -o "$TARBALL" "$ASSET_URL"

  EXTRACT_DIR="$TMPDIR_WORK/extract_$ARCH_LABEL"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$TARBALL" -C "$EXTRACT_DIR"

  # Find the bumblebee binary
  BINARY=$(find "$EXTRACT_DIR" -name "bumblebee" -type f | head -1)
  if [ -n "$BINARY" ]; then
    cp "$BINARY" "$RESOURCES_DIR/bumblebee_$ARCH_LABEL"
    chmod 755 "$RESOURCES_DIR/bumblebee_$ARCH_LABEL"
    echo "  ✓ bumblebee_$ARCH_LABEL installed"
  else
    echo "  [!] bumblebee binary not found in tarball for $ARCH_LABEL"
  fi

  # Extract threat_intel on first arch only
  if [ "$ARCH_LABEL" = "arm64" ]; then
    THREAT_INTEL=$(find "$EXTRACT_DIR" -name "threat_intel" -type d | head -1)
    if [ -n "$THREAT_INTEL" ]; then
      rm -rf "$RESOURCES_DIR/threat_intel"
      cp -R "$THREAT_INTEL" "$RESOURCES_DIR/threat_intel"
      echo "  ✓ threat_intel installed"
    else
      echo "  [!] threat_intel directory not found in tarball"
    fi
  fi
}

mkdir -p "$RESOURCES_DIR"
download_and_extract arm64 arm64
download_and_extract x86_64 amd64

echo ""
echo "Done. Resources in: $RESOURCES_DIR"
echo "Open BumblebeeGUI.xcodeproj in Xcode and build."
