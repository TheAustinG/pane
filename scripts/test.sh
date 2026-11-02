#!/usr/bin/env bash
# Usage: scripts/test.sh [--packages-only | --build-only]
# Runs the PaneCore package tests on the Mac, regenerates the Xcode project,
# then builds the Pane scheme for the generic tvOS Simulator with signing
# disabled. build-for-testing also compiles the PaneUITests bundle, so a
# rename that breaks the UI tests fails here.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

mode="all"
case "${1:-}" in
  "") ;;
  --packages-only) mode="packages" ;;
  --build-only) mode="build" ;;
  *) die "unknown argument: $1 (see -h)" ;;
esac

use_xcode
cd "$PANE_ROOT"

if [[ "$mode" != "build" ]]; then
  echo "== PaneCore tests"
  swift test --package-path Packages/PaneCore
fi

if [[ "$mode" != "packages" ]]; then
  echo "== generate project"
  "$PANE_ROOT/scripts/gen.sh"
  echo "== build Pane (tvOS Simulator)"
  xcodebuild build-for-testing \
    -project Pane.xcodeproj \
    -scheme Pane \
    -configuration Debug \
    -destination 'generic/platform=tvOS Simulator' \
    -derivedDataPath build/DerivedData-sim \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
  echo "ok: Pane built"
fi
