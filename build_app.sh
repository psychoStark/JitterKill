#!/usr/bin/env bash
# build_app.sh — Build JitterKill.app from the Swift package
# Usage: ./build_app.sh [--install]  (--install copies to /Applications)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$SCRIPT_DIR"
APP_NAME="JitterKill"
VERSION="1.0"
BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
PLIST_SRC="$PKG_DIR/Sources/JitterKillApp/Resources/Info.plist"

# Parse arguments
TARGET_ARCH="universal"
INSTALL_APP=false

for arg in "$@"; do
  case "$arg" in
    arm64|aarch64)
      TARGET_ARCH="arm64"
      ;;
    x86_64|x86|intel)
      TARGET_ARCH="x86_64"
      ;;
    universal|fat|all)
      TARGET_ARCH="universal"
      ;;
    --install|-i)
      INSTALL_APP=true
      ;;
  esac
done

echo ""
echo "🔨 Building $APP_NAME.app v$VERSION ($TARGET_ARCH) …"
echo "   Package: $PKG_DIR"
echo ""

# 1. Build Release binary
cd "$PKG_DIR"
if [ "$TARGET_ARCH" = "arm64" ]; then
  echo "⚙️  Compiling Apple Silicon (arm64) Binary…"
  swift build -c release --arch arm64
elif [ "$TARGET_ARCH" = "x86_64" ]; then
  echo "⚙️  Compiling Intel (x86_64) Binary…"
  swift build -c release --arch x86_64
else
  echo "⚙️  Compiling Universal Binary (arm64 + x86_64)…"
  swift build -c release --arch arm64 --arch x86_64 2>&1 || swift build -c release 2>&1
fi

BINARY=""
for candidate in \
  "$PKG_DIR/.build/out/Products/Release/JitterKill" \
  "$PKG_DIR/.build/apple/Products/Release/JitterKill" \
  "$PKG_DIR/.build/release/JitterKill"; do
  if [ -f "$candidate" ]; then
    BINARY="$candidate"
    break
  fi
done

if [ -z "$BINARY" ]; then
  echo "❌ Build failed — binary not found"
  exit 1
fi

echo "   Binary architecture: $(lipo -archs "$BINARY" 2>/dev/null || echo "native")"

# 2. Assemble .app bundle
echo ""
echo "📦 Assembling $APP_NAME.app …"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PLIST_SRC" "$BUNDLE/Contents/Info.plist"

# Copy embedded helper & CLI scripts into the app bundle
RESOURCES_SRC="$PKG_DIR/Sources/JitterKillApp/Resources"
if [ -f "$RESOURCES_SRC/jitterkill-helper.sh" ]; then
  cp "$RESOURCES_SRC/jitterkill-helper.sh" "$BUNDLE/Contents/Resources/"
  cp "$RESOURCES_SRC/jitterkill-cli.sh"    "$BUNDLE/Contents/Resources/"
else
  cp "$SCRIPT_DIR/scripts/jitterkill-helper.sh" "$BUNDLE/Contents/Resources/"
  cp "$SCRIPT_DIR/scripts/jitterkill-cli.sh"    "$BUNDLE/Contents/Resources/"
fi
chmod +x "$BUNDLE/Contents/Resources/"*.sh

# Copy app icon and image resources into the app bundle
if [ -f "$RESOURCES_SRC/AppIcon.icns" ]; then
  cp "$RESOURCES_SRC/AppIcon.icns" "$BUNDLE/Contents/Resources/"
fi
cp "$RESOURCES_SRC"/*.png "$BUNDLE/Contents/Resources/" 2>/dev/null || true

# Copy any xcassets if present
ASSETS_SRC="$PKG_DIR/Sources/JitterKillApp/Resources/Assets.xcassets"
if [ -d "$ASSETS_SRC" ]; then
  echo "   Including Assets.xcassets …"
  xcrun actool --compile "$BUNDLE/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist /dev/null \
    "$ASSETS_SRC" >/dev/null 2>&1 || true
fi

# 3. Ad-hoc code sign (allows running without Apple Developer account)
echo "🔑 Code signing (ad-hoc) …"
codesign --force --deep --sign - "$BUNDLE"

# 4. Remove quarantine flag (so macOS doesn't block it)
xattr -cr "$BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Built: $BUNDLE"
echo ""

# 5. Optional install to /Applications
if [ "$INSTALL_APP" = true ]; then
  echo "📲 Installing to /Applications/$APP_NAME.app …"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$BUNDLE" "/Applications/$APP_NAME.app"
  echo "✅ Installed! You can now launch JitterKill from /Applications."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Launch: open \"$BUNDLE\""
echo "  Install: ./build_app.sh --install"
echo "  Build DMG: ./build_dmg.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
