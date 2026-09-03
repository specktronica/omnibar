#!/usr/bin/env bash
# Completely uninstall Omnibar: running process, Applications copies, Homebrew
# cask and tap, login item, Dock backup, preferences, TCC grants, and caches.
#
#   make remove
#
# Does not delete repo build products (build/Omnibar.app, DerivedData).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="io.specktronica.omnibar"
CASK="omnibar"
TAP="specktronica/omnibar"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

remove_app() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  echo "Deleting $path"
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$path" 2>/dev/null || true
  fi
  if ! rm -rf "$path"; then
    echo "Could not delete $path" >&2
  fi
}

quit_omnibar
restore_dock
remove_login_item

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

echo "Resetting TCC grants."
tccutil reset All "$BUNDLE_ID" 2>/dev/null \
  || {
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
  }

if command -v brew >/dev/null 2>&1 && brew tap | grep -qx "$TAP"; then
  echo "Untapping $TAP."
  brew untap "$TAP" || echo "Homebrew untap failed." >&2
fi

if command -v sfltool >/dev/null 2>&1 && sfltool dumpbtm 2>/dev/null | grep -q "$BUNDLE_ID"; then
  echo "A leftover Login Item may still appear in System Settings → General → Login Items. Disable it there."
fi

echo "Omnibar removed. Repo build products were left in place."
