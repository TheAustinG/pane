#!/usr/bin/env bash
# Usage: scripts/sim.sh <command> [options]
# Builds, runs and inspects apps in the tvOS Simulator. Never touches a physical device.
# The simulator is the one named $PANE_SIM_NAME (default "Apple TV 4K (3rd generation)").
#
# Commands:
#   udid                      Print the simulator UDID, creating the simulator on the
#                             newest tvOS runtime if it does not exist.
#   boot [--show]             Boot the simulator and wait until it is ready. --show also
#                             opens Simulator.app.
#   run [--root DIR] [--scheme NAME] [--no-build] [--show] [-- launch args...]
#                             Generate the project in DIR (default: this repo, must contain
#                             project.yml), build Debug with signing on into
#                             DIR/build/DerivedData-sim, install, relaunch and pass the args
#                             after -- to the app. The scheme defaults to the app target.
#   shot PATH                 Save a screenshot to PATH.
#   record PATH SECONDS       Record the screen to PATH for SECONDS seconds.
#   container [--root DIR] [--scheme NAME]
#                             Print the app's data container path.
#   stop [--root DIR] [--scheme NAME]
#                             Terminate the app.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
case "${1:-}" in -h|--help) show_usage "${BASH_SOURCE[0]}"; exit 0 ;; esac

use_xcode
need_cmd python3 "Install python3."

DEFAULT_SIM_NAME="Apple TV 4K (3rd generation)"
DEFAULT_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K"
SIM_NAME="${PANE_SIM_NAME:-$DEFAULT_SIM_NAME}"

find_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"tvOS-([0-9-]+)$", runtime)
    if not m:
        continue
    version = tuple(int(p) for p in m.group(1).split("-"))
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True):
            if best is None or version > best[0]:
                best = (version, d["udid"])
if best is None:
    sys.exit(1)
print(best[1])
' "$SIM_NAME"
}

newest_tvos_runtime() {
  xcrun simctl list runtimes available -j | python3 -c '
import json, sys
best = None
for r in json.load(sys.stdin)["runtimes"]:
    if r.get("platform") != "tvOS" or not r.get("isAvailable", True):
        continue
    version = tuple(int(p) for p in r["version"].split("."))
    if best is None or version > best[0]:
        best = (version, r["identifier"])
if best is None:
    sys.exit(1)
print(best[1])
'
}

device_type_for_name() {
  if [[ "$SIM_NAME" == "$DEFAULT_SIM_NAME" ]]; then
    echo "$DEFAULT_DEVICE_TYPE"
    return 0
  fi
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
for t in json.load(sys.stdin)["devicetypes"]:
    if t["name"] == sys.argv[1]:
        print(t["identifier"])
        sys.exit(0)
sys.exit(1)
' "$SIM_NAME"
}

sim_udid() {
  local udid runtime device_type
  udid="$(find_udid || true)"
  if [[ -n "$udid" ]]; then
    echo "$udid"
    return 0
  fi
  runtime="$(newest_tvos_runtime)" || die "no tvOS simulator runtime is installed."
  device_type="$(device_type_for_name)" || die "no simulator device type named '$SIM_NAME'."
  echo "creating simulator '$SIM_NAME' on $runtime" >&2
  xcrun simctl create "$SIM_NAME" "$device_type" "$runtime"
}

sim_boot() {
  local udid="$1" show="$2"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  if [[ "$show" == 1 ]]; then
    open -a Simulator --args -CurrentDeviceUDID "$udid"
  fi
}

ROOT=""
SCHEME=""
NO_BUILD=0
SHOW=0
LAUNCH_ARGS=()

parse_project_args() {
  ROOT="$PANE_ROOT"
  SCHEME=""
  NO_BUILD=0
  SHOW=0
  LAUNCH_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) [[ $# -ge 2 ]] || die "--root needs a directory"; ROOT="$2"; shift 2 ;;
      --scheme) [[ $# -ge 2 ]] || die "--scheme needs a name"; SCHEME="$2"; shift 2 ;;
      --no-build) NO_BUILD=1; shift ;;
      --show) SHOW=1; shift ;;
      --) shift; LAUNCH_ARGS=("$@"); break ;;
      *) die "unknown argument: $1 (see -h)" ;;
    esac
  done
  [[ -d "$ROOT" ]] || die "no such directory: $ROOT"
  ROOT="$(cd "$ROOT" && pwd)"
  [[ -f "$ROOT/project.yml" ]] || die "$ROOT has no project.yml"
}

project_name() {
  awk '/^name:/ { print $2; exit }' "$ROOT/project.yml"
}

xcodeproj_path() {
  local name
  name="$(project_name)"
  [[ -n "$name" ]] || die "project.yml in $ROOT has no top-level name"
  echo "$ROOT/$name.xcodeproj"
}

generate_project() {
  need_cmd xcodegen "Run scripts/bootstrap.sh."
  (cd "$ROOT" && xcodegen generate --spec project.yml --quiet)
}

ensure_project() {
  [[ -d "$(xcodeproj_path)" ]] || generate_project >&2
}

default_scheme() {
  local scheme
  scheme="$(awk '
    /^targets:/ { in_targets = 1; next }
    in_targets && /^[^ #]/ { in_targets = 0 }
    in_targets && /^  [A-Za-z0-9_.-]+:[ ]*$/ { name = $1; sub(/:$/, "", name) }
    in_targets && /^    type: *application/ { print name; exit }
  ' "$ROOT/project.yml")"
  if [[ -z "$scheme" ]]; then
    scheme="$(xcodebuild -list -json -project "$(xcodeproj_path)" | python3 -c '
import json, sys
schemes = json.load(sys.stdin)["project"]["schemes"]
print(schemes[0] if schemes else "")
')"
  fi
  [[ -n "$scheme" ]] || die "could not determine the app scheme; pass --scheme"
  echo "$scheme"
}

BUNDLE_ID=""
TEAM=""
APP_PATH=""

resolve_app() {
  local udid="$1" out err
  err="$(mktemp)"
  out="$(xcodebuild -showBuildSettings -json \
    -project "$(xcodeproj_path)" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=tvOS Simulator,id=$udid" \
    -derivedDataPath "$ROOT/build/DerivedData-sim" 2>"$err" | python3 -c '
import json, sys
for entry in json.load(sys.stdin):
    s = entry["buildSettings"]
    if s.get("PRODUCT_TYPE") == "com.apple.product-type.application":
        print(s["PRODUCT_BUNDLE_IDENTIFIER"])
        print(s.get("DEVELOPMENT_TEAM", ""))
        print(s["TARGET_BUILD_DIR"] + "/" + s["FULL_PRODUCT_NAME"])
        sys.exit(0)
sys.exit(1)
')" || { cat "$err" >&2; rm -f "$err"; die "could not read build settings for scheme '$SCHEME'"; }
  rm -f "$err"
  BUNDLE_ID="$(sed -n 1p <<<"$out")"
  TEAM="$(sed -n 2p <<<"$out")"
  APP_PATH="$(sed -n 3p <<<"$out")"
}

cmd_udid() {
  sim_udid
}

cmd_boot() {
  local show=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --show) show=1; shift ;;
      *) die "unknown argument: $1 (see -h)" ;;
    esac
  done
  local udid
  udid="$(sim_udid)"
  sim_boot "$udid" "$show"
  echo "booted $SIM_NAME ($udid)"
}

cmd_run() {
  parse_project_args "$@"
  local udid
  udid="$(sim_udid)"
  sim_boot "$udid" "$SHOW"

  if [[ "$NO_BUILD" == 0 ]] || [[ ! -d "$(xcodeproj_path)" ]]; then
    echo "== generate project"
    generate_project
  fi
  [[ -n "$SCHEME" ]] || SCHEME="$(default_scheme)"

  if [[ "$NO_BUILD" == 0 ]]; then
    echo "== build $SCHEME (Debug, tvOS Simulator)"
    xcodebuild build \
      -project "$(xcodeproj_path)" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "platform=tvOS Simulator,id=$udid" \
      -derivedDataPath "$ROOT/build/DerivedData-sim" \
      -quiet
  fi

  resolve_app "$udid"
  if [[ -n "$TEAM" ]]; then
    echo "DEVELOPMENT_TEAM: $TEAM"
  else
    echo "warning: DEVELOPMENT_TEAM is empty. Set PANE_TEAM_ID in local/Signing.local.xcconfig." >&2
  fi
  [[ -d "$APP_PATH" ]] || die "expected build output not found: $APP_PATH"

  echo "== install $BUNDLE_ID"
  xcrun simctl install "$udid" "$APP_PATH"
  if [[ "$SCHEME" == "$(default_scheme)" ]]; then
    echo "$BUNDLE_ID" > "$ROOT/build/sim-bundle-id"
  fi
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "== launch $BUNDLE_ID"
  xcrun simctl launch "$udid" "$BUNDLE_ID" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
}

cmd_shot() {
  [[ $# -eq 1 ]] || die "usage: sim.sh shot PATH"
  mkdir -p "$(dirname "$1")"
  xcrun simctl io "$(sim_udid)" screenshot "$1"
}

cmd_record() {
  [[ $# -eq 2 ]] || die "usage: sim.sh record PATH SECONDS"
  local path="$1" duration="$2"
  [[ "$duration" =~ ^[0-9]+$ ]] || die "SECONDS must be a whole number"
  mkdir -p "$(dirname "$path")"
  local udid pid
  udid="$(sim_udid)"
  xcrun simctl io "$udid" recordVideo --codec h264 --force "$path" &
  pid=$!
  sleep "$duration"
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" || true
  [[ -s "$path" ]] || die "recording was not written to $path"
  echo "recorded $path"
}

installed_bundle_id() {
  local cache="$ROOT/build/sim-bundle-id"
  if [[ -z "$SCHEME" && -s "$cache" ]]; then
    BUNDLE_ID="$(cat "$cache")"
    return 0
  fi
  ensure_project
  [[ -n "$SCHEME" ]] || SCHEME="$(default_scheme)"
  resolve_app "$1"
}

cmd_container() {
  parse_project_args "$@"
  local udid
  udid="$(sim_udid)"
  installed_bundle_id "$udid"
  xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data
}

cmd_stop() {
  parse_project_args "$@"
  local udid
  udid="$(sim_udid)"
  installed_bundle_id "$udid"
  xcrun simctl terminate "$udid" "$BUNDLE_ID"
  echo "stopped $BUNDLE_ID"
}

command="${1:-}"
[[ -n "$command" ]] || { show_usage "${BASH_SOURCE[0]}"; exit 1; }
shift
case "$command" in
  udid) cmd_udid "$@" ;;
  boot) cmd_boot "$@" ;;
  run) cmd_run "$@" ;;
  shot) cmd_shot "$@" ;;
  record) cmd_record "$@" ;;
  container) cmd_container "$@" ;;
  stop) cmd_stop "$@" ;;
  *) die "unknown command: $command (see -h)" ;;
esac
