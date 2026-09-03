#!/usr/bin/env bash
# Publish build/Omnibar-<version>.zip to a GitHub Release and bump the Homebrew cask.
# Requires the zip from `make release` (notarized; SKIP_NOTARY archives are rejected).
#
#   make publish
#   make release publish
#   DRY_RUN=1 make publish
#   FORCE=1 make publish          # replace same-version zip and cask sha256
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

TAG="v${VERSION}"
ZIP="build/Omnibar-${VERSION}.zip"
TAP_REPO="${TAP_REPO:-specktronica/homebrew-omnibar}"
CASK_PATH="Casks/omnibar.rb"
ASSET_NAME="Omnibar-${VERSION}.zip"
RELEASE_ASSET_URL="https://github.com/specktronica/omnibar/releases/download/${TAG}/${ASSET_NAME}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required (brew install gh) and must be authenticated for specktronica." >&2
  exit 1
fi

if [[ ! -f "$ZIP" ]]; then
  echo "Missing $ZIP. Run: make release" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

origin_tap_url() {
  if [[ -n "${TAP_URL:-}" ]]; then
    printf '%s\n' "$TAP_URL"
    return
  fi
  local origin
  origin="$(git remote get-url origin)"
  if [[ "$origin" =~ ^(git@[^:]+):([^/]+)/[^/]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}/homebrew-omnibar.git"
  elif [[ "$origin" =~ ^(https://[^/]+)/([^/]+)/ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/homebrew-omnibar.git"
  else
    echo "Could not derive ${TAP_REPO} clone URL from origin '$origin'. Set TAP_URL." >&2
    exit 1
  fi
}

patch_cask() {
  VERSION="$1" SHA256="$2" python3 -c '
import os, re, sys
text = sys.stdin.read()
version = os.environ["VERSION"]
sha = os.environ["SHA256"]
text, n_ver = re.subn(r"(?m)^  version \"[^\"]+\"", f"  version \"{version}\"", text, count=1)
text, n_sha = re.subn(r"(?m)^  sha256 \"[0-9a-fA-F]+\"", f"  sha256 \"{sha}\"", text, count=1)
if n_ver != 1 or n_sha != 1:
    sys.exit(f"could not patch cask (version replacements={n_ver}, sha256 replacements={n_sha})")
sys.stdout.write(text)
'
}

cask_field() {
  FIELD="$1" python3 -c '
import os, re, sys
text = sys.stdin.read()
field = os.environ["FIELD"]
m = re.search(rf"(?m)^  {re.escape(field)} \"([^\"]+)\"", text)
if not m:
    sys.exit(f"no {field} in cask")
print(m.group(1))
'
}

echo "Publish $TAG"
echo "  zip:    $ZIP"
echo "  sha256: $SHA256"

EXTRACT="$(mktemp -d "${TMPDIR:-/tmp}/omnibar-publish.XXXXXX")"
TAP_DIR=""
cleanup() { rm -rf "$EXTRACT" "${TAP_DIR:-}"; }
trap cleanup EXIT

ditto -x -k "$ZIP" "$EXTRACT"
if [[ ! -d "$EXTRACT/Omnibar.app" ]]; then
  echo "$ZIP does not contain Omnibar.app at the root." >&2
  exit 1
fi
if ! stapler_out="$(xcrun stapler validate "$EXTRACT/Omnibar.app" 2>&1)"; then
  echo "$stapler_out" >&2
  echo "$ZIP is not stapled. Run make release without SKIP_NOTARY=1." >&2
  exit 1
fi

git fetch origin >/dev/null

REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/${TAG}^{}" | awk '{print $1}')"
if [[ -z "$REMOTE_TAG_SHA" ]]; then
  REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/${TAG}" | awk '{print $1}')"
fi
LOCAL_TAG_SHA=""
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  LOCAL_TAG_SHA="$(git rev-parse "${TAG}^{commit}")"
fi

if [[ -n "$REMOTE_TAG_SHA" && -n "$LOCAL_TAG_SHA" && "$REMOTE_TAG_SHA" != "$LOCAL_TAG_SHA" ]]; then
  echo "Tag $TAG is ${LOCAL_TAG_SHA} locally and ${REMOTE_TAG_SHA} on origin." >&2
  exit 1
fi

NEED_TAG=0
if [[ -z "$REMOTE_TAG_SHA" && -z "$LOCAL_TAG_SHA" ]]; then
  NEED_TAG=1
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty; commit before tagging $TAG." >&2
    exit 1
  fi
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$BRANCH" != "main" ]]; then
    echo "Create $TAG from main (currently ${BRANCH})." >&2
    exit 1
  fi
  git fetch origin main >/dev/null
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "HEAD must match origin/main before tagging $TAG." >&2
    exit 1
  fi
  HEAD_VERSION="$(git show HEAD:project.yml | awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }')"
  if [[ "$HEAD_VERSION" != "$VERSION" ]]; then
    echo "HEAD project.yml MARKETING_VERSION is '${HEAD_VERSION}', expected '${VERSION}'." >&2
    exit 1
  fi
fi

release_json=""
if gh release view "$TAG" >/dev/null 2>&1; then
  release_json="$(gh release view "$TAG" --json assets)"
fi

remote_digest=""
if [[ -n "$release_json" ]]; then
  remote_digest="$(python3 -c '
import json,sys
name = sys.argv[1]
data = json.load(sys.stdin)
for a in data.get("assets") or []:
    if a.get("name") == name:
        d = a.get("digest") or ""
        print(d.split(":", 1)[-1] if d else "")
        break
' "$ASSET_NAME" <<<"$release_json")"
fi

if [[ -n "$remote_digest" && "$remote_digest" != "$SHA256" && "${FORCE:-}" != "1" ]]; then
  echo "GitHub release $TAG already has ${ASSET_NAME} with sha256 ${remote_digest}." >&2
  echo "Local zip is ${SHA256}. Set FORCE=1 to replace the asset." >&2
  exit 1
fi

remote_cask="$(gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" | python3 -c '
import json, sys, base64
print(base64.b64decode(json.load(sys.stdin)["content"]).decode())
')"
CURRENT_VERSION="$(cask_field version <<<"$remote_cask")"
CURRENT_SHA="$(cask_field sha256 <<<"$remote_cask")"
TAP_UP_TO_DATE=0
if [[ "$CURRENT_VERSION" == "$VERSION" && "$CURRENT_SHA" == "$SHA256" ]]; then
  TAP_UP_TO_DATE=1
fi
if [[ "$CURRENT_VERSION" == "$VERSION" && "$CURRENT_SHA" != "$SHA256" && "${FORCE:-}" != "1" ]]; then
  echo "Cask ${CASK_PATH} is already version ${VERSION} with sha256 ${CURRENT_SHA}." >&2
  echo "Local zip is ${SHA256}. Set FORCE=1 to update the cask." >&2
  exit 1
fi

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "DRY_RUN=1; no GitHub or tap changes"
  if [[ "$NEED_TAG" -eq 1 ]]; then
    echo "Would tag and push $TAG at $(git rev-parse --short HEAD)"
  fi
  if [[ -z "$release_json" ]]; then
    echo "Would create GitHub release $TAG with $ZIP"
  elif [[ -z "$remote_digest" ]]; then
    echo "Would upload $ZIP to existing release $TAG"
  elif [[ "$remote_digest" != "$SHA256" ]]; then
    echo "Would replace $ASSET_NAME on release $TAG"
  else
    echo "GitHub release $TAG already has this zip"
  fi
  if [[ "$TAP_UP_TO_DATE" -eq 1 ]]; then
    echo "Homebrew cask already at ${VERSION} (${SHA256})"
  else
    echo "Would update ${TAP_REPO} ${CASK_PATH} ${CURRENT_VERSION} -> ${VERSION} sha256 ${SHA256}"
  fi
  exit 0
fi

if [[ "$NEED_TAG" -eq 1 ]]; then
  git tag -a "$TAG" -m "Omnibar ${VERSION}"
  git push origin "refs/tags/${TAG}"
  echo "Pushed tag $TAG"
elif [[ -n "$LOCAL_TAG_SHA" && -z "$REMOTE_TAG_SHA" ]]; then
  git push origin "refs/tags/${TAG}"
  echo "Pushed existing tag $TAG"
fi

if [[ -z "$release_json" ]]; then
  gh release create "$TAG" "$ZIP" --title "Omnibar ${VERSION}" --generate-notes
  echo "Created GitHub release $TAG"
elif [[ -z "$remote_digest" ]]; then
  gh release upload "$TAG" "$ZIP"
  echo "Uploaded $ASSET_NAME to $TAG"
elif [[ "$remote_digest" != "$SHA256" ]]; then
  gh release upload "$TAG" "$ZIP" --clobber
  echo "Replaced $ASSET_NAME on $TAG"
else
  echo "GitHub release $TAG already has this zip"
fi

ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsL -r 0-0 -o /dev/null "$RELEASE_ASSET_URL"; then
    ok=1
    break
  fi
  sleep 2
done
if [[ "$ok" -ne 1 ]]; then
  echo "Release asset is not downloadable yet: $RELEASE_ASSET_URL" >&2
  exit 1
fi

if [[ "$TAP_UP_TO_DATE" -eq 1 ]]; then
  echo "Homebrew cask already at ${VERSION} (${SHA256})"
  exit 0
fi

TAP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omnibar-tap.XXXXXX")"
git clone --depth 1 "$(origin_tap_url)" "$TAP_DIR"
CASK="${TAP_DIR}/${CASK_PATH}"
if [[ ! -f "$CASK" ]]; then
  echo "Cask not found at ${CASK_PATH} in ${TAP_REPO}." >&2
  exit 1
fi

patch_cask "$VERSION" "$SHA256" <"$CASK" >"${CASK}.new"
mv "${CASK}.new" "$CASK"
git -C "$TAP_DIR" add "$CASK_PATH"
git -C "$TAP_DIR" commit -m "Update omnibar cask to ${VERSION}."
git -C "$TAP_DIR" push origin HEAD
echo "Updated ${TAP_REPO} ${CASK_PATH} to ${VERSION}"
echo "Install: brew upgrade --cask specktronica/omnibar/omnibar"
