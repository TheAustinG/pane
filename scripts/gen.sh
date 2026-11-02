#!/usr/bin/env bash
# Usage: scripts/gen.sh
# Generates Pane.xcodeproj from project.yml with XcodeGen.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

need_cmd xcodegen "Run scripts/bootstrap.sh."
cd "$PANE_ROOT"
xcodegen generate --spec project.yml --quiet
echo "generated Pane.xcodeproj"
