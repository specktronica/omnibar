#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

CONFIGURATION="${1:-Release}"
DERIVED="build/DerivedData"

xcodebuild \
  -project Omnibar.xcodeproj \
  -scheme Omnibar \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  build

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name "Omnibar.app" | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  echo "Omnibar.app not found in build products" >&2
  exit 1
fi

mkdir -p build
rm -rf build/Omnibar.app
cp -R "$APP_SRC" build/Omnibar.app

codesign --force --deep --sign - \
  --entitlements Omnibar/Resources/Omnibar.entitlements \
  --options runtime \
  build/Omnibar.app

echo "Built build/Omnibar.app"
