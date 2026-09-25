#!/usr/bin/env bash
# Delete repo build products: build/Omnibar.app, build/DerivedData, and release zips.
#
#   make clean
#
# Quits Omnibar only when the running copy lives under build/, so that copy can
# restore the Dock before its bundle disappears. An Applications or Homebrew
# install is left running. This does not uninstall that install; use `make remove`.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
BUILD="$ROOT/build"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_ID="io.specktronica.omnibar"

# Physical path, so /var and /private/var (and other symlinks) compare equal.
physical() {
  local path="$1"
  (cd "$path" && pwd -P)
}

# True when a running Omnibar's bundle is inside this repo's build directory.
running_from_build() {
  [[ -d "$BUILD" ]] || return 1
  pgrep -x Omnibar >/dev/null 2>&1 || return 1

  local build_real path path_real line pid cmd
  build_real="$(physical "$BUILD")"

  path="$(osascript -e 'tell application "System Events" to POSIX path of application file of (first process whose name is "Omnibar")' 2>/dev/null || true)"
  if [[ -n "$path" && -d "$path" ]]; then
    path_real="$(physical "$path")"
    [[ "$path_real" == "$build_real" || "$path_real" == "$build_real"/* ]]
    return
  fi

  # Match only the Omnibar executable. Other tools can have build/ paths in
  # their arguments while an Applications copy is the one actually running.
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    pid="${line%% *}"
    cmd="${line#"$pid"}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    case "$cmd" in
      "$BUILD"/Omnibar.app/Contents/MacOS/Omnibar|\
      "$BUILD"/Omnibar.app/Contents/MacOS/Omnibar\ *|\
      "$build_real"/Omnibar.app/Contents/MacOS/Omnibar|\
      "$build_real"/Omnibar.app/Contents/MacOS/Omnibar\ *|\
      "$BUILD"/DerivedData/Build/Products/*/Omnibar.app/Contents/MacOS/Omnibar|\
      "$BUILD"/DerivedData/Build/Products/*/Omnibar.app/Contents/MacOS/Omnibar\ *|\
      "$build_real"/DerivedData/Build/Products/*/Omnibar.app/Contents/MacOS/Omnibar|\
      "$build_real"/DerivedData/Build/Products/*/Omnibar.app/Contents/MacOS/Omnibar\ *)
        return 0 ;;
    esac
  done < <(ps -axww -o pid=,command=)

  if [[ -x /usr/sbin/lsof ]]; then
    local product holder comm
    for product in \
      "$BUILD"/Omnibar.app/Contents/MacOS/Omnibar \
      "$BUILD"/DerivedData/Build/Products/*/Omnibar.app/Contents/MacOS/Omnibar
    do
      [[ -e "$product" ]] || continue
      while IFS= read -r holder; do
        [[ -n "$holder" ]] || continue
        comm="$(ps -p "$holder" -o comm= 2>/dev/null || true)"
        comm="${comm##*/}"
        comm="${comm#"${comm%%[![:space:]]*}"}"
        comm="${comm%"${comm##*[![:space:]]}"}"
        [[ "$comm" == "Omnibar" ]] && return 0
      done < <(/usr/sbin/lsof -t "$product" 2>/dev/null || true)
    done
  fi
  return 1
}

quit_build_copy() {
  echo "Quitting Omnibar launched from build/."
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
    sleep 0.2
  fi
  if running_from_build; then
    echo "Omnibar is still running from build/. Stop it, then run make clean again." >&2
    exit 1
  fi
}

if running_from_build; then
  quit_build_copy
fi

if [[ -x "$LSREGISTER" && -d "$BUILD" ]]; then
  product_list=("$BUILD"/Omnibar.app "$BUILD"/DerivedData/Build/Products/*/Omnibar.app)
  for product in "${product_list[@]}"; do
    [[ -d "$product" ]] || continue
    "$LSREGISTER" -u "$product" 2>/dev/null || true
  done
fi

if [[ -d "$BUILD" ]]; then
  rm -rf "$BUILD"
  echo "Removed build/."
else
  echo "No build/ directory."
fi
