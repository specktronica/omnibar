#!/usr/bin/env bash
# Fail if signing keys, private keys, or GitHub tokens are about to be committed
# (default: staged files) or are already tracked (--tracked).
set -euo pipefail
cd "$(dirname "$0")/.."

mode="staged"
if [[ "${1:-}" == "--tracked" ]]; then
  mode="tracked"
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--tracked]" >&2
  exit 2
fi

blocked_name() {
  local base
  base="$(basename "$1")"
  case "$base" in
    *.p8|*.p12|*.pfx|*.p15|*.key|*.mobileprovision)
      return 0
      ;;
    AuthKey_*)
      return 0
      ;;
  esac
  return 1
}

scan_file() {
  local f="$1"
  [[ -z "$f" ]] && return 0
  if blocked_name "$f"; then
    echo "blocked secret file: $f" >&2
    return 1
  fi
  [[ -f "$f" ]] || return 0
  # Split markers so this script is not a false positive.
  local pem_re ssh_re
  pem_re='-----BEGIN ([A-Z0-9]+ )?PRIV''ATE KEY-----'
  ssh_re='-----BEGIN OPENSSH PRIV''ATE KEY-----'
  if grep -qEI -e "$pem_re" -e "$ssh_re" -- "$f"; then
    echo "blocked private key material: $f" >&2
    return 1
  fi
  if grep -qEI -e 'gho_[A-Za-z0-9]{36,}' -e 'github_pat_[A-Za-z0-9_]{20,}' -- "$f"; then
    echo "blocked GitHub token: $f" >&2
    return 1
  fi
  return 0
}

errors=0
if [[ "$mode" == "tracked" ]]; then
  list_cmd=(git ls-files -z)
else
  list_cmd=(git diff --cached --name-only --diff-filter=ACM -z)
fi

while IFS= read -r -d '' f; do
  if ! scan_file "$f"; then
    errors=1
  fi
done < <("${list_cmd[@]}")

if [[ "$errors" -ne 0 ]]; then
  echo "Remove these files from git. Signing keys and notary credentials stay in Keychain, not the repo." >&2
  exit 1
fi
