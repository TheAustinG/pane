#!/usr/bin/env bash
# Sourced by the other scripts. Not meant to be run directly.

PANE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PANE_ROOT

die() {
  echo "error: $*" >&2
  exit 1
}

use_xcode() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return 0
  fi
  local selected
  selected="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ "$selected" == *.app/Contents/Developer* ]]; then
    return 0
  fi
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    return 0
  fi
  die "Xcode not found at /Applications/Xcode.app."
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

show_usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$1"
}

want_help() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help) return 0 ;;
    esac
  done
  return 1
}
