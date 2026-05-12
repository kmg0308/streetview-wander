#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="StreetViewWander"
DISPLAY_NAME="StreetView Wander"
EXECUTABLE_NAME="StreetViewWander"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
BUILD_COMMIT="${BUILD_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)}"
DEFAULT_REPOSITORY="${DEFAULT_REPOSITORY:-${GITHUB_REPOSITORY:-}}"

if [[ -z "$DEFAULT_REPOSITORY" ]]; then
  ORIGIN_URL="$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || true)"
  if [[ "$ORIGIN_URL" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    DEFAULT_REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
fi

if [[ -z "$DEFAULT_REPOSITORY" ]]; then
  DEFAULT_REPOSITORY="kmg0308/streetview-wander"
fi

DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

swift run StreetViewWanderSelfTest
swift build -c release --product "$EXECUTABLE_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/data"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/data/countries.json" "$APP_DIR/Contents/Resources/data/countries.json"
swift "$ROOT_DIR/scripts/make_icon.swift" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.kangmingyu.streetviewwander</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Local-only random Street View explorer.</string>
    <key>SWBuildCommit</key>
    <string>$BUILD_COMMIT</string>
    <key>SWGitHubRepository</key>
    <string>$DEFAULT_REPOSITORY</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
fi

ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"
PKG_PATH="$DIST_DIR/$APP_NAME-$VERSION.pkg"
FIXED_ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
FIXED_PKG_PATH="$DIST_DIR/$APP_NAME.pkg"
PKG_ROOT="$DIST_DIR/.pkg-root"
PKG_COMPONENTS="$DIST_DIR/.pkg-components.plist"

rm -f "$ZIP_PATH" "$PKG_PATH" "$FIXED_ZIP_PATH" "$FIXED_PKG_PATH"
(
  cd "$DIST_DIR"
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP_NAME.app" "$ZIP_PATH"
)
cp "$ZIP_PATH" "$FIXED_ZIP_PATH"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
ditto --norsrc --noextattr "$APP_DIR" "$PKG_ROOT/Applications/$APP_NAME.app"
cat > "$PKG_COMPONENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <false/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
    <key>RootRelativeBundlePath</key>
    <string>Applications/$APP_NAME.app</string>
  </dict>
</array>
</plist>
PLIST
COPYFILE_DISABLE=1 pkgbuild \
  --root "$PKG_ROOT" \
  --component-plist "$PKG_COMPONENTS" \
  --install-location "/" \
  --identifier "com.kangmingyu.streetviewwander.pkg" \
  --version "$VERSION" \
  "$PKG_PATH" >/dev/null
rm -rf "$PKG_ROOT"
rm -f "$PKG_COMPONENTS"
cp "$PKG_PATH" "$FIXED_PKG_PATH"

cat > "$DIST_DIR/manifest.json" <<JSON
{
  "name": "$APP_NAME",
  "displayName": "$DISPLAY_NAME",
  "version": "$VERSION",
  "build": "$BUILD_NUMBER",
  "commit": "$BUILD_COMMIT",
  "repository": "$DEFAULT_REPOSITORY",
  "zip": "$(basename "$ZIP_PATH")",
  "pkg": "$(basename "$PKG_PATH")",
  "latestZip": "$(basename "$FIXED_ZIP_PATH")",
  "latestPkg": "$(basename "$FIXED_PKG_PATH")"
}
JSON

echo "Built $APP_DIR"
echo "Built $ZIP_PATH"
echo "Built $PKG_PATH"
echo "Built $FIXED_ZIP_PATH"
echo "Built $FIXED_PKG_PATH"
