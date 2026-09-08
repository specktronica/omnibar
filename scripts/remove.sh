#!/usr/bin/env bash
# Completely uninstall Omnibar: running process, Applications copies, Homebrew
# cask and tap, Xcode DerivedData products, login item, Dock backup,
# preferences, TCC grants, and caches.
#
#   make remove
#
# Does not delete repo build products (build/Omnibar.app, build/DerivedData).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="io.specktronica.omnibar"
CASK="omnibar"
TAP="specktronica/omnibar"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
XCODE_DERIVED="${HOME}/Library/Developer/Xcode/DerivedData"

echo "Removing Omnibar."

quit_omnibar() {
  if ! pgrep -x Omnibar >/dev/null 2>&1; then
    return 0
  fi
  echo "Quitting Omnibar."
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  local i=0
  while pgrep -x Omnibar >/dev/null 2>&1 && (( i < 50 )); do
    sleep 0.1
    i=$((i + 1))
  done
  if pgrep -x Omnibar >/dev/null 2>&1; then
    killall Omnibar 2>/dev/null || true
    sleep 0.3
  fi
  if pgrep -x Omnibar >/dev/null 2>&1; then
    killall -9 Omnibar 2>/dev/null || true
  fi
}

restore_dock() {
  local tmp orientation delay modifier autohide restored=0
  tmp="$(mktemp -t omnibar-prefs)"
  if defaults export "$BUNDLE_ID" "$tmp" 2>/dev/null \
    && /usr/libexec/PlistBuddy -c 'Print :omnibar.dock.backup.v1' "$tmp" >/dev/null 2>&1; then
    if autohide="$(/usr/libexec/PlistBuddy -c 'Print :omnibar.dock.backup.v1:autohide' "$tmp" 2>/dev/null)"; then
      if [[ "$autohide" == "true" ]]; then
        defaults write com.apple.dock autohide -bool true
      else
        defaults write com.apple.dock autohide -bool false
      fi
      restored=1
    fi
    if delay="$(/usr/libexec/PlistBuddy -c 'Print :omnibar.dock.backup.v1:autohide-delay' "$tmp" 2>/dev/null)"; then
      defaults write com.apple.dock autohide-delay -float "$delay"
      restored=1
    fi
    if modifier="$(/usr/libexec/PlistBuddy -c 'Print :omnibar.dock.backup.v1:autohide-time-modifier' "$tmp" 2>/dev/null)"; then
      defaults write com.apple.dock autohide-time-modifier -float "$modifier"
      restored=1
    fi
    if orientation="$(/usr/libexec/PlistBuddy -c 'Print :omnibar.dock.backup.v1:orientation' "$tmp" 2>/dev/null)"; then
      defaults write com.apple.dock orientation -string "$orientation"
      restored=1
    fi
  fi
  rm -f "$tmp"

  if (( restored )); then
    echo "Restored Dock from Omnibar backup."
    killall Dock 2>/dev/null || true
    return 0
  fi

  delay="$(defaults read com.apple.dock autohide-delay 2>/dev/null || true)"
  orientation="$(defaults read com.apple.dock orientation 2>/dev/null || true)"
  if [[ -n "$delay" && -n "$orientation" ]] \
    && awk -v d="$delay" 'BEGIN { exit !(d + 0 == 1000) }' \
    && [[ "$orientation" == "top" ]]; then
    echo "Restored Dock from fully-hidden signature."
    defaults write com.apple.dock autohide-delay -float 0.5
    defaults write com.apple.dock autohide-time-modifier -float 1
    defaults write com.apple.dock orientation -string bottom
    killall Dock 2>/dev/null || true
  fi
}

remove_login_item() {
  osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  if exists login item "Omnibar" then
    delete login item "Omnibar"
  end if
end tell
EOF
}

unregister_app() {
  local path="$1"
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$path" 2>/dev/null || true
  fi
}

remove_app() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  echo "Deleting $path"
  unregister_app "$path"
  if ! rm -rf "$path"; then
    echo "Could not delete $path" >&2
  fi
}

# Xcode IDE builds land in ~/Library/Developer/Xcode/DerivedData, not the
# repo's build/DerivedData. Launch Services often prefers that copy, so
# Accessibility and Screen Recording bind to it instead of build/Omnibar.app.
remove_xcode_derived_apps() {
  local app
  [[ -d "$XCODE_DERIVED" ]] || return 0
  shopt -s nullglob
  for app in "$XCODE_DERIVED"/Omnibar-*/Build/Products/*/Omnibar.app; do
    remove_app "$app"
  done
  shopt -u nullglob
}

# Every Launch Services record for this bundle ID, including stale temp and
# Trash paths. path: comes before identifier: in each dump record.
registered_omnibar_paths() {
  [[ -x "$LSREGISTER" ]] || return 0
  "$LSREGISTER" -dump 2>/dev/null | awk -v bid="$BUNDLE_ID" '
    /^-+$/ {
      if (want && path != "") print path
      path = ""
      want = 0
      next
    }
    /^path:[[:space:]]+/ {
      line = $0
      sub(/^path:[[:space:]]+/, "", line)
      sub(/ \([^)]+\)$/, "", line)
      path = line
      next
    }
    /^identifier:[[:space:]]+/ {
      want = ($2 == bid)
      next
    }
    END {
      if (want && path != "") print path
    }
  ' || true
}

unregister_registered_copies() {
  local path
  local any=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if (( !any )); then
      echo "Unregistering Launch Services copies."
      any=1
    fi
    unregister_app "$path"
  done < <(registered_omnibar_paths | awk 'NF && !seen[$0]++')
}

# tccutil looks up the bundle ID through Launch Services. An unregistered or
# already-deleted copy yields "No such bundle identifier", or a silent no-op.
# Prefer an installed copy, then the leftover repo build.
tcc_app_candidate() {
  local path
  for path in \
    "/Applications/Omnibar.app" \
    "${HOME}/Applications/Omnibar.app" \
    "$PWD/build/Omnibar.app"
  do
    if [[ -d "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  if [[ -d "$XCODE_DERIVED" ]]; then
    shopt -s nullglob
    for path in "$XCODE_DERIVED"/Omnibar-*/Build/Products/*/Omnibar.app; do
      shopt -u nullglob
      printf '%s\n' "$path"
      return 0
    done
    shopt -u nullglob
  fi
  return 1
}

reset_tcc() {
  local candidate=""
  local failed=0
  candidate="$(tcc_app_candidate || true)"
  if [[ -n "$candidate" && -x "$LSREGISTER" ]]; then
    echo "Registering $candidate so TCC reset can resolve $BUNDLE_ID."
    "$LSREGISTER" -f "$candidate" || true
    sleep 0.5
  else
    echo "No Omnibar.app found to register; TCC reset may not take effect." >&2
  fi

  echo "Resetting TCC grants."
  if tccutil reset All "$BUNDLE_ID"; then
    return 0
  fi
  echo "tccutil reset All failed; trying Accessibility and ScreenCapture." >&2
  if ! tccutil reset Accessibility "$BUNDLE_ID"; then
    echo "Could not reset Accessibility for $BUNDLE_ID." >&2
    failed=1
  fi
  if ! tccutil reset ScreenCapture "$BUNDLE_ID"; then
    echo "Could not reset Screen Recording for $BUNDLE_ID." >&2
    failed=1
  fi
  if (( failed )); then
    echo "TCC grants may still be active. After registering a copy, run:" >&2
    echo "  tccutil reset Accessibility $BUNDLE_ID" >&2
    echo "  tccutil reset ScreenCapture $BUNDLE_ID" >&2
  fi
}

quit_omnibar
restore_dock
remove_login_item
reset_tcc

# Unregister before brew deletes the files so Launch Services does not keep a
# stale /Applications/Omnibar.app entry for the bundle ID.
unregister_app "/Applications/Omnibar.app"
unregister_app "${HOME}/Applications/Omnibar.app"

if command -v brew >/dev/null 2>&1; then
  if brew list --cask "$CASK" >/dev/null 2>&1; then
    echo "Uninstalling Homebrew cask $CASK."
    brew uninstall --cask --zap "$CASK" || echo "Homebrew cask uninstall failed." >&2
  elif brew list --cask "${TAP}/${CASK}" >/dev/null 2>&1; then
    echo "Uninstalling Homebrew cask ${TAP}/${CASK}."
    brew uninstall --cask --zap "${TAP}/${CASK}" || echo "Homebrew cask uninstall failed." >&2
  else
    echo "Homebrew cask $CASK is not installed."
  fi
else
  echo "Homebrew is not on PATH; skipping cask uninstall."
fi

remove_app "/Applications/Omnibar.app"
remove_app "${HOME}/Applications/Omnibar.app"
remove_xcode_derived_apps
unregister_registered_copies

echo "Deleting preferences and caches."
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf \
  "${HOME}/Library/Preferences/${BUNDLE_ID}.plist" \
  "${HOME}/Library/Preferences/${BUNDLE_ID}.plist.lockfile" \
  "${HOME}/Library/Caches/${BUNDLE_ID}" \
  "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState" \
  "${HOME}/Library/HTTPStorages/${BUNDLE_ID}" \
  "${HOME}/Library/WebKit/${BUNDLE_ID}" \
  "${HOME}/Library/Application Support/Omnibar" \
  "${HOME}/Library/Application Support/${BUNDLE_ID}" \
  "${HOME}/Library/Containers/${BUNDLE_ID}" \
  "${HOME}/Library/Logs/Omnibar"
rm -f "${HOME}/Library/Preferences/ByHost/${BUNDLE_ID}".*.plist 2>/dev/null || true

if command -v brew >/dev/null 2>&1 && brew tap | grep -qx "$TAP"; then
  echo "Untapping $TAP."
  brew untap "$TAP" || echo "Homebrew untap failed." >&2
fi

if command -v sfltool >/dev/null 2>&1 && sfltool dumpbtm 2>/dev/null | grep -q "$BUNDLE_ID"; then
  echo "A leftover Login Item may still appear in System Settings → General → Login Items. Disable it there."
fi

echo "Omnibar removed. Repo build products (build/Omnibar.app, build/DerivedData) were left in place."
