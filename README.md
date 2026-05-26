# Bumblebee GUI

A native macOS wrapper for [Bumblebee](https://github.com/perplexityai/bumblebee) — Perplexity's open-source supply chain threat scanner.

Bumblebee scans your project dependencies and system packages against a threat intelligence catalogue, flagging malicious or suspicious packages. This app provides a point-and-click interface instead of the raw JSON output from the CLI.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- Scan any folder with a single click
- Three scan profiles: Baseline (system packages), Project (dependencies), Deep (full folder)
- Results displayed with colour-coded severity badges, grouped by ecosystem
- Threat intel updates checked against GitHub releases on every launch, applied in-app without a rebuild
- Universal binary — runs natively on Apple Silicon and Intel

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later

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

## Distribution (notarisation)

For a notarised build you need to sign the bundled bumblebee binaries with your Developer ID before archiving:

```sh
codesign -s "Developer ID Application: Your Name (TEAMID)" \
  BumblebeeGUI/Resources/bumblebee_arm64 \
  BumblebeeGUI/Resources/bumblebee_x86_64
```

Then archive in Xcode and submit for notarisation as normal.

## Project structure

```
BumblebeeGUI/
├── BumblebeeGUIApp.swift       app entry point
├── ScanModels.swift            data types (ScanPackage, ScanFinding, ScanProfile)
├── BumblebeeRunner.swift       runs the CLI, streams and parses NDJSON output
├── ThreatIntelUpdater.swift    checks GitHub releases and applies threat intel updates
├── ContentView.swift           all views
└── Resources/
    ├── bumblebee_arm64         downloaded by setup.sh — not committed
    ├── bumblebee_x86_64        downloaded by setup.sh — not committed
    └── threat_intel/           committed; updated in-app
```

## Licence

This project is an independent GUI wrapper and is not affiliated with Perplexity AI. Bumblebee itself is licenced under the [Apache 2.0 licence](https://github.com/perplexityai/bumblebee/blob/main/LICENSE).
