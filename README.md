# Bumblebee GUI

A native macOS wrapper for [Bumblebee](https://github.com/perplexityai/bumblebee) — Perplexity's open-source supply chain threat scanner.

Bumblebee scans your project dependencies and system packages against a threat intelligence catalogue, flagging malicious or suspicious packages. This app provides a point-and-click interface instead of the raw JSON output from the CLI.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- Scan any folder with a single click
- Three scan profiles: Baseline (system packages), Project (dependencies), Deep (full folder)
- Preferences window (⌘,) — set a default scan folder, default scan type, and whether to check for cloud files before scanning
- Cancel a running scan at any time — partial results are preserved and clearly marked incomplete
- Results displayed with colour-coded severity badges, grouped by ecosystem
- Per-ecosystem filter field for large package sets (ecosystems over 100 packages show a live search field)
- Pre-scan check for iCloud/Dropbox placeholder files that would trigger downloads (can be disabled in preferences)
- Threat intel updates checked against GitHub releases on every launch, applied in-app without a rebuild
- Universal binary — runs natively on Apple Silicon and Intel

## Download

Pre-built, signed, and notarised DMGs are available on the [Releases](https://github.com/kai-h/bumblebee-gui/releases) page.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (only needed if building from source)

## Setup

The bumblebee binaries are not committed to this repository. Run the setup script once before building to download the latest release:

```sh
./setup.sh
```

This fetches the `arm64` and `x86_64` bumblebee binaries and places them in `BumblebeeGUI/Resources/`. The threat intel catalogue is committed to the repo and kept up to date in-app, but `setup.sh` will also refresh it from the latest release if you prefer.

## Building

Open `BumblebeeGUI.xcodeproj` in Xcode, select the **BumblebeeGUI** scheme, and press **Run** (⌘R).

Set your Development Team in **Signing & Capabilities** before building for distribution.

## Updating bumblebee

**Binaries** — re-run `setup.sh` to pull a newer release into `Resources/`, then rebuild the app.

**Threat intel** — the app checks for updates on every launch and shows a banner when one is available. Click **Update Now** to download and apply it without a rebuild.

## Distribution (release script)

`release.sh` handles the full release pipeline — signing, archiving, export, notarisation, DMG creation, and optional upload to GitHub Releases:

```sh
./release.sh
```

Prerequisites:

```sh
brew install create-dmg gh
```

Store your notarisation credentials once:

```sh
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "app-specific-password"
```

Copy `.env.example` to `.env` and fill in `TEAM_ID`, `SIGN_ID`, and `NOTARY_PROFILE` before running the script. At the end of a successful build, the script asks whether to push the DMG to GitHub as a new release.

## Project structure

```
BumblebeeGUI/
├── BumblebeeGUIApp.swift       app entry point; registers the Settings scene
├── ScanModels.swift            data types (ScanPackage, ScanFinding, ScanProfile)
├── BumblebeeRunner.swift       runs the CLI, streams and parses NDJSON output
├── ThreatIntelUpdater.swift    checks GitHub releases and applies threat intel updates
├── AppPreferences.swift        UserDefaults-backed preferences (folder, profile, cloud check)
├── ContentView.swift           main window views
├── PreferencesView.swift       Settings window (⌘,)
└── Resources/
    ├── bumblebee_arm64         downloaded by setup.sh — not committed
    ├── bumblebee_x86_64        downloaded by setup.sh — not committed
    └── threat_intel/           committed; updated in-app
```

## Licence

This project is an independent GUI wrapper and is not affiliated with Perplexity AI. Bumblebee itself is licenced under the [Apache 2.0 licence](https://github.com/perplexityai/bumblebee/blob/main/LICENSE).
