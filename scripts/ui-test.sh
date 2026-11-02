#!/usr/bin/env bash
# Usage: scripts/ui-test.sh
# Runs the PaneUITests on the tvOS Simulator named $PANE_SIM_NAME (default
# "Apple TV 4K (3rd generation)"), creating it if it does not exist.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

use_xcode
cd "$PANE_ROOT"
udid="$("$PANE_ROOT/scripts/sim.sh" udid)"
"$PANE_ROOT/scripts/gen.sh"
xcodebuild test \
  -project Pane.xcodeproj \
  -scheme Pane \
  -destination "platform=tvOS Simulator,id=$udid" \
  -derivedDataPath "${PANE_DERIVED_DATA:-build/DerivedData-uitest}" \
  -only-testing:PaneUITests \
  -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
echo "ok: UI tests passed"
