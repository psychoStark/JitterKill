#!/usr/bin/env bash
# build_dmg.sh — Package JitterKill into distributable .dmg installers
# Usage:
#   ./build_dmg.sh              # Builds all: arm64, x86_64, and universal
#   ./build_dmg.sh --all        # Builds all: arm64, x86_64, and universal
#   ./build_dmg.sh arm64        # Builds Apple Silicon DMG only
#   ./build_dmg.sh x86_64       # Builds Intel DMG only
#   ./build_dmg.sh universal    # Builds Universal 2 DMG only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="JitterKill"
VERSION="1.0"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
TEMP_DMG_DIR="$SCRIPT_DIR/.dmg_temp"

# Determine target architectures to build
TARGET_ARCHES=()

if [ $# -eq 0 ]; then
  TARGET_ARCHES=("arm64" "x86_64" "universal")
else
  for arg in "$@"; do
    case "$arg" in
      all|--all)
        TARGET_ARCHES=("arm64" "x86_64" "universal")
        break
        ;;
      arm64|aarch64|apple-silicon)
        TARGET_ARCHES+=("arm64")
        ;;
      x86_64|x86|intel)
        TARGET_ARCHES+=("x86_64")
        ;;
      universal|fat)
        TARGET_ARCHES+=("universal")
        ;;
      *)
        echo "Unknown target architecture: $arg"
        echo "Usage: ./build_dmg.sh [arm64|x86_64|universal|--all]"
        exit 1
        ;;
    esac
  done
fi

build_single_dmg() {
  local arch="$1"
  local dmg_name=""

  if [ "$arch" = "arm64" ]; then
    dmg_name="${APP_NAME}-v${VERSION}-arm64.dmg"
  elif [ "$arch" = "x86_64" ]; then
    dmg_name="${APP_NAME}-v${VERSION}-x86_64.dmg"
  elif [ "$arch" = "universal" ]; then
    dmg_name="${APP_NAME}-v${VERSION}-universal.dmg"
  else
    dmg_name="${APP_NAME}-v${VERSION}-${arch}.dmg"
  fi

  local dmg_output="$SCRIPT_DIR/$dmg_name"

  echo "========================================================"
  echo "🚀 Building DMG for $APP_NAME v$VERSION ($arch)"
  echo "   Output target: $dmg_name"
  echo "========================================================"

  # 1. Compile and assemble app bundle for this architecture
  "$SCRIPT_DIR/build_app.sh" "$arch"

  # 2. Prepare clean staging directory
  rm -rf "$TEMP_DMG_DIR" "$dmg_output"
  mkdir -p "$TEMP_DMG_DIR"

  # 3. Copy app bundle into staging
  echo "📋 Copying $APP_NAME.app into disk image staging..."
  cp -R "$APP_BUNDLE" "$TEMP_DMG_DIR/"

  # 4. Create Applications shortcut symlink
  echo "🔗 Creating /Applications drag-and-drop symlink..."
  ln -s /Applications "$TEMP_DMG_DIR/Applications"

  # 5. Set custom volume icon if AppIcon.icns exists
  if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$TEMP_DMG_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$TEMP_DMG_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$TEMP_DMG_DIR" 2>/dev/null || true
  fi

  # 6. Generate compressed UDZO DMG using hdiutil
  # Volume title is strictly APP_NAME without version, as requested
  echo "💿 Compressing disk image ($dmg_name)..."
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TEMP_DMG_DIR" \
    -ov \
    -format UDZO \
    "$dmg_output"

  # Clean up staging
  rm -rf "$TEMP_DMG_DIR"

  echo "✅ Built $dmg_name ($(du -h "$dmg_output" | cut -f1 | tr -d ' '))"
  echo ""
}

echo ""
echo "🏗️  Starting JitterKill DMG Build Pipeline..."
echo "    Targets to build: ${TARGET_ARCHES[*]}"
echo ""

GENERATED_DMGS=()

for arch in "${TARGET_ARCHES[@]}"; do
  build_single_dmg "$arch"
  if [ "$arch" = "arm64" ]; then
    GENERATED_DMGS+=("${APP_NAME}-v${VERSION}-arm64.dmg")
  elif [ "$arch" = "x86_64" ]; then
    GENERATED_DMGS+=("${APP_NAME}-v${VERSION}-x86_64.dmg")
  elif [ "$arch" = "universal" ]; then
    GENERATED_DMGS+=("${APP_NAME}-v${VERSION}-universal.dmg")
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 All requested DMG packages generated successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for dmg in "${GENERATED_DMGS[@]}"; do
  if [ -f "$SCRIPT_DIR/$dmg" ]; then
    size=$(du -h "$SCRIPT_DIR/$dmg" | cut -f1 | tr -d ' ')
    echo "  • $dmg ($size)"
  fi
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
