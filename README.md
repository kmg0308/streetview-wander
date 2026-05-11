# StreetView Wander

[![Download for macOS](https://img.shields.io/badge/Download%20for%20macOS-PKG-0A84FF?style=for-the-badge&logo=apple)](https://github.com/kmg0308/streetview-wander/releases/latest/download/StreetViewWander.pkg)

[Latest Release](https://github.com/kmg0308/streetview-wander/releases/latest) · [Download ZIP](https://github.com/kmg0308/streetview-wander/releases/latest/download/StreetViewWander.zip)

StreetView Wander is a macOS app for jumping to random Google Street View panoramas.

The app is local-first. API keys are entered by the user on their Mac and are not bundled into releases.

## Features

- Native macOS app built with SwiftUI.
- Full-window Google Street View through a WKWebView.
- Random panorama search using Google Street View metadata.
- Worldwide, continent, and country scope filters.
- Floating mini map for the selected panorama.
- Local visit history.
- `.env` import for user-owned Google API keys.
- GitHub Release update check and one-click app update.
- PKG installer and ZIP update archive from GitHub Releases.

## Install

1. Download the latest PKG:

```text
https://github.com/kmg0308/streetview-wander/releases/latest/download/StreetViewWander.pkg
```

2. Open the installer.
3. Launch `StreetView Wander` from `/Applications`.
4. Open Settings and add your Google API keys.

If macOS blocks the first launch because the build is ad-hoc signed, right click the app in Finder and choose `Open`.

## Google Cloud Setup

Create two API keys in Google Cloud:

1. Browser key
   - Enable API: Maps JavaScript API
   - API restriction: Maps JavaScript API
   - If you use website restrictions, allow:
     - `http://127.0.0.1:5173/*`
     - `http://localhost:5173/*`
   - Store it as `VITE_GOOGLE_MAPS_API_KEY`

2. Metadata key
   - Enable API: Street View Static API
   - API restriction: Street View Static API
   - Store it as `GOOGLE_STREET_VIEW_METADATA_API_KEY`

The app can import a `.env` file with this shape:

```bash
VITE_GOOGLE_MAPS_API_KEY=your_browser_key
GOOGLE_STREET_VIEW_METADATA_API_KEY=your_metadata_key
```

For the browser key, Google Maps JavaScript runs inside a macOS `WKWebView` with a local base URL of `http://127.0.0.1:5173/`.

## Updates

StreetView Wander checks the latest GitHub Release when the app opens and then every 6 hours while it is running. Open the Updates sheet or press the update banner when a newer release is available.

- The app downloads the Release asset named `StreetViewWander.zip`.
- It replaces the installed `StreetViewWander.app`.
- It relaunches the app after installing.
- The PKG is for first install. The ZIP is for in-app updates.

For updates to work for normal users, the Release assets must be publicly downloadable. If this repository stays private, use a public release-only repository or add a user-provided GitHub token flow before distributing to others.

## Automatic Release From Main

The workflow at `.github/workflows/release.yml` builds and publishes release assets whenever `main` receives a push.

```text
push to main
-> GitHub Actions builds StreetViewWander.app
-> creates StreetViewWander.zip and StreetViewWander.pkg
-> publishes a GitHub Release
-> installed apps detect the new Release
```

The workflow uses GitHub's `GITHUB_TOKEN`. It does not require a paid Apple Developer account. Builds are ad-hoc signed by default, so Gatekeeper may show a first-launch warning.

## Build

```bash
swift build
swift run StreetViewWanderSelfTest
./scripts/package.sh
```

Packaged files are written to `dist/`:

- `StreetViewWander.app`
- `StreetViewWander.zip`
- `StreetViewWander.pkg`
- versioned ZIP and PKG copies

## Local Data

Country boundary data lives in `data/countries.json` and is bundled into the app at package time.

Visit history is saved locally:

```text
~/Library/Application Support/StreetView Wander/history.json
```

## Requirements

- macOS 13 or later.
- Swift 6 toolchain for building from source.
