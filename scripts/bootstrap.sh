#!/usr/bin/env bash
# Usage: scripts/bootstrap.sh
# Checks Xcode 27, installs XcodeGen with Homebrew if missing, enables the
# repo git hooks and creates the gitignored local/ files the secret scan needs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

cd "$PANE_ROOT"

xcode_app=/Applications/Xcode.app
[[ -d "$xcode_app" ]] || die "Xcode not found at $xcode_app."
use_xcode
version_line="$(xcodebuild -version 2>/dev/null | sed -n 1p || true)"
[[ "$version_line" =~ ^Xcode\ 27(\.|$) ]] || die "Expected Xcode 27, found '${version_line:-none}'."
echo "ok: $version_line"

if [[ "$(/usr/bin/xcode-select -p)" != *.app/Contents/Developer* ]]; then
  echo "note: xcode-select still points at Command Line Tools. Scripts set DEVELOPER_DIR themselves;"
  echo "      to fix it system-wide run: sudo xcode-select -s $xcode_app"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  need_cmd brew "Install Homebrew from https://brew.sh, then rerun."
  echo "installing xcodegen with Homebrew"
  brew install xcodegen
fi
echo "ok: $(xcodegen --version | head -n 1)"

git config core.hooksPath scripts/hooks
chmod +x scripts/*.sh scripts/hooks/*
echo "ok: git hooks path is $(git config --get core.hooksPath)"

mkdir -p local
[[ -f local/Secrets.local.xcconfig ]] || cp Config/Secrets.example.xcconfig local/Secrets.local.xcconfig
[[ -f local/denylist.txt ]] || printf '# One literal per line that must never be committed.\n' > local/denylist.txt
echo "ok: local/ has Secrets.local.xcconfig and denylist.txt"
