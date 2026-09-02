#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

CONFIGURATION="${1:-Release}"
DERIVED="build/DerivedData"

# TCC (Accessibility / Screen Recording) records a code-signing requirement for
# the app. With an ad-hoc signature that requirement is a cdhash, which changes
# on every build, so the grant stops matching the new binary. Prefer a real
# identity from the keychain so the requirement is stable across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development'; then
    IDENTITY="Apple Development"
  else
    IDENTITY="-"
  fi
fi

SIGN_OVERRIDES=()
if [[ "$IDENTITY" == "-" ]]; then
  echo "No Apple Development identity found; using ad-hoc signing." >&2
  echo "Accessibility must be granted again after each rebuild." >&2
  SIGN_OVERRIDES=(CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual)
fi

xcodebuild \
  -project Omnibar.xcodeproj \
  -scheme Omnibar \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  ${SIGN_OVERRIDES[@]+"${SIGN_OVERRIDES[@]}"} \
  build

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name "Omnibar.app" | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  echo "Omnibar.app not found in build products" >&2
  exit 1
fi

mkdir -p build
rm -rf build/Omnibar.app
cp -R "$APP_SRC" build/Omnibar.app

codesign --force --deep --sign "$IDENTITY" \
  --entitlements Omnibar/Resources/Omnibar.entitlements \
  --options runtime \
  build/Omnibar.app

echo "Built build/Omnibar.app (signed with: $IDENTITY)"
codesign -d -r- build/Omnibar.app 2>&1 | grep designated || true
