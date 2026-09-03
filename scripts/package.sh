#!/usr/bin/env bash
# Developer ID build → notarize → staple → zip for GitHub Releases / Homebrew.
# Requires a Developer ID Application identity and a notarytool keychain profile.
#
#   make release
#   NOTARYTOOL_PROFILE=my-profile make release
#   SKIP_NOTARY=1 make release   # zip only; Gatekeeper will not accept the zip
set -euo pipefail
cd "$(dirname "$0")/.."

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

json_field() {
  python3 -c 'import json,sys
raw = sys.stdin.read()
i = raw.find("{")
if i < 0:
    sys.exit("notarytool output had no JSON object")
obj = json.loads(raw[i:])
print(obj.get(sys.argv[1], ""))
' "$1"
}

# Apple Development identities include an email. Keep it out of logs and screenshots.
redact_identity() {
  sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted>/g'
}

chmod +x scripts/check-secrets.sh
./scripts/check-secrets.sh --tracked

NEEDLE="${CODESIGN_IDENTITY:-Developer ID Application}"
IDENTITY_HASH="$(identity_hash "$NEEDLE")"
if [[ -z "$IDENTITY_HASH" ]]; then
  echo "No Developer ID Application identity found in the keychain." >&2
  echo "Install a Developer ID Application certificate for this team, or set CODESIGN_IDENTITY to its hash." >&2
  echo "Do not paste 'security find-identity' output into issues or chat; it can include personal Apple IDs." >&2
  exit 1
fi

IDENTITY_LABEL="$(identity_name "$IDENTITY_HASH")"
if [[ "$IDENTITY_LABEL" != "Developer ID Application:"* ]]; then
  echo "Release signing resolved to '$(redact_identity <<<"$IDENTITY_LABEL")'; it must be Developer ID Application." >&2
  exit 1
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

echo "Release $VERSION — signing with $(redact_identity <<<"$IDENTITY_LABEL")"

export CODESIGN_IDENTITY="$IDENTITY_HASH"
export ARCHS="${ARCHS:-arm64 x86_64}"
chmod +x scripts/build.sh
./scripts/build.sh Release

BIN="build/Omnibar.app/Contents/MacOS/Omnibar"
ARCH_INFO="$(lipo -info "$BIN" 2>/dev/null || true)"
if [[ "$ARCH_INFO" != *"arm64"* || "$ARCH_INFO" != *"x86_64"* ]]; then
  echo "Release binary must be universal (arm64 + x86_64). Got: ${ARCH_INFO:-missing}" >&2
  exit 1
fi

codesign --force --deep --sign "$IDENTITY_HASH" \
  --entitlements Omnibar/Resources/Omnibar.entitlements \
  --options runtime \
  --timestamp \
  build/Omnibar.app

ZIP="build/Omnibar-${VERSION}.zip"
SUBMIT_ZIP="build/Omnibar-${VERSION}-submit.zip"
rm -f "$ZIP" "$SUBMIT_ZIP"
ditto -c -k --keepParent build/Omnibar.app "$SUBMIT_ZIP"

if [[ "${SKIP_NOTARY:-}" == "1" ]]; then
  mv "$SUBMIT_ZIP" "$ZIP"
  echo "Skipped notarization (SKIP_NOTARY=1). This zip will not pass Gatekeeper." >&2
else
  PROFILE="${NOTARYTOOL_PROFILE:-notarytool-specktronica}"
  echo "Submitting $SUBMIT_ZIP to Apple notary (profile: $PROFILE)..."
  if ! JSON="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$PROFILE" --wait --output-format json)"; then
    echo "notarytool submit failed for profile '$PROFILE'." >&2
    echo "Create the profile interactively (it prompts; do not put a password on the command line or in git):" >&2
    echo "  xcrun notarytool store-credentials $PROFILE" >&2
    echo "Or set NOTARYTOOL_PROFILE to an existing keychain profile." >&2
    exit 1
  fi
  STATUS="$(json_field status <<<"$JSON")"
  SUB_ID="$(json_field id <<<"$JSON")"
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization status: ${STATUS:-unknown} (id: ${SUB_ID:-none})" >&2
    if [[ -n "$SUB_ID" ]]; then
      mkdir -p build
      xcrun notarytool log "$SUB_ID" --keychain-profile "$PROFILE" >build/notary-log.json 2>/dev/null || true
      echo "Wrote build/notary-log.json (gitignored). Do not commit or paste it." >&2
    fi
    exit 1
  fi
  xcrun stapler staple build/Omnibar.app
  xcrun stapler validate build/Omnibar.app
  rm -f "$SUBMIT_ZIP"
  ditto -c -k --keepParent build/Omnibar.app "$ZIP"
fi

echo "Signed with: $(redact_identity <<<"$IDENTITY_LABEL")"
echo "Release zip: $ZIP"
shasum -a 256 "$ZIP"
