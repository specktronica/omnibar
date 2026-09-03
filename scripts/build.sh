#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

CONFIGURATION="${1:-Release}"
DERIVED="build/DerivedData"

# SHA-1 of the first valid codesigning identity whose common name equals
# needle, equals the hash needle, or starts with needle.
identity_hash() {
  local needle="$1"
  security find-identity -v -p codesigning 2>/dev/null | awk -v needle="$needle" '
    /^ *[0-9]+\) / && $2 ~ /^[A-F0-9]+$/ {
      hash = $2
      if (!match($0, /"[^"]+"/)) next
      name = substr($0, RSTART + 1, RLENGTH - 2)
      if (hash == needle || name == needle || index(name, needle) == 1) {
        print hash
        exit
      }
    }
  '
}

identity_name() {
  local hash="$1"
  security find-identity -v -p codesigning 2>/dev/null | awk -v hash="$hash" '
    /^ *[0-9]+\) / && $2 == hash {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  '
}

redact_identity() {
  sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted>/g'
}

# TCC (Accessibility / Screen Recording) records a code-signing requirement for
# the app. With an ad-hoc signature that requirement is a cdhash, which changes
# on every build, so the grant stops matching the new binary. Prefer a real
# identity from the keychain so the requirement is stable across rebuilds.
#
# CODESIGN_IDENTITY is optional. If it is unset, or set to a name that is not
# in the keychain (a leftover Developer ID export with the wrong legal name is
# the usual case), fall back to Apple Development so `make run` still works.
REQUESTED="${CODESIGN_IDENTITY:-}"
IDENTITY_HASH=""
if [[ -n "$REQUESTED" ]]; then
  IDENTITY_HASH="$(identity_hash "$REQUESTED")"
  if [[ -z "$IDENTITY_HASH" ]]; then
    echo "CODESIGN_IDENTITY is not in the keychain." >&2
    hint="$(identity_hash "Developer ID Application")"
    if [[ -n "$hint" ]]; then
      echo "A Developer ID Application identity is installed; set CODESIGN_IDENTITY to its hash if you meant to use it." >&2
    fi
    echo "Falling back to Apple Development for this local build." >&2
  fi
fi

if [[ -z "$IDENTITY_HASH" ]]; then
  IDENTITY_HASH="$(identity_hash "Apple Development")"
fi

SIGN_OVERRIDES=()
if [[ -z "$IDENTITY_HASH" ]]; then
  IDENTITY="-"
  IDENTITY_LABEL="ad-hoc"
  echo "No Apple Development identity found; using ad-hoc signing." >&2
  echo "Accessibility must be granted again after each rebuild." >&2
  SIGN_OVERRIDES=(CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual)
else
  IDENTITY="$IDENTITY_HASH"
  IDENTITY_LABEL="$(identity_name "$IDENTITY_HASH")"
  # Hash is unique when two Developer ID certs share a common name.
  SIGN_OVERRIDES=(CODE_SIGN_IDENTITY="$IDENTITY_HASH")
fi

# ARCHS= (unset) builds the host architecture. Release packaging sets
# ARCHS="arm64 x86_64" so the zip is universal.
DESTINATION="platform=macOS"
ARCH_OVERRIDES=()
if [[ -n "${ARCHS:-}" ]]; then
  DESTINATION="generic/platform=macOS"
  ARCH_OVERRIDES=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=)
fi

xcodebuild \
  -project Omnibar.xcodeproj \
  -scheme Omnibar \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "$DESTINATION" \
  ${SIGN_OVERRIDES[@]+"${SIGN_OVERRIDES[@]}"} \
  ${ARCH_OVERRIDES[@]+"${ARCH_OVERRIDES[@]}"} \
  build

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name "Omnibar.app" | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  echo "Omnibar.app not found in build products" >&2
  exit 1
fi

mkdir -p build
rm -rf build/Omnibar.app
ditto "$APP_SRC" build/Omnibar.app

codesign --force --deep --sign "$IDENTITY" \
  --entitlements Omnibar/Resources/Omnibar.entitlements \
  --options runtime \
  build/Omnibar.app

echo "Built build/Omnibar.app (signed with: $(redact_identity <<<"$IDENTITY_LABEL"))"
codesign -d -r- build/Omnibar.app 2>&1 | grep designated | redact_identity || true
