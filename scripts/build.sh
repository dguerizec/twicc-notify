#!/usr/bin/env bash
# Build the release APK
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

cd "$PROJECT_DIR"

echo "Building release APK..."
flutter build apk --release

echo ""
echo "APK built: $APK_PATH"
echo "Size: $(du -h "$APK_PATH" | cut -f1)"
