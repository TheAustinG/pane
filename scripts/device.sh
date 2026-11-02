#!/usr/bin/env bash
# Usage: PANE_DEVICE_PASS=1 scripts/device.sh
# Builds Debug for the paired Apple TV with -allowProvisioningUpdates (the
# destination is that device's UDID so the provisioning profile includes it),
# installs and launches on it, then prints the provisioning profile expiry.
# Refuses to run unless PANE_DEVICE_PASS=1 is set, because it changes what is
# installed on a real device.
# Set PANE_DEVICE (name, UDID or identifier) to pick a specific device.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

if [[ "${PANE_DEVICE_PASS:-}" != "1" ]]; then
  die "refusing to touch a physical device. This script installs and launches on a real Apple TV; rerun with PANE_DEVICE_PASS=1 to allow it. Use scripts/sim.sh to run in the simulator."
fi

use_xcode
need_cmd python3 "Install python3."
cd "$PANE_ROOT"

find_device() {
  local json found
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 \
    || { rm -f "$json"; die "devicectl could not list devices. Is Xcode 27 installed and selected?"; }
  found="$(WANT="${PANE_DEVICE:-}" python3 - "$json" <<'PY'
import json
import os
import sys

want = os.environ["WANT"]
with open(sys.argv[1]) as f:
    devices = json.load(f)["result"]["devices"]
for d in devices:
    props = d.get("properties", {})
    hw = props.get("hardware") or d.get("hardwareProperties", {})
    conn = props.get("connection") or d.get("connectionProperties", {})
    name = (props.get("state") or d.get("deviceProperties", {})).get("name", "")
    if hw.get("platform") != "tvOS" or hw.get("reality") == "simulated":
        continue
    if conn.get("pairingState") != "paired":
        continue
    if want and want not in (d.get("identifier"), hw.get("udid"), name):
        continue
    print(hw["udid"])
    break
PY
)"
  rm -f "$json"
  if [[ -n "${PANE_DEVICE:-}" ]]; then
    [[ -n "$found" ]] || die "no paired Apple TV matches PANE_DEVICE. Run 'xcrun devicectl list devices'."
  else
    [[ -n "$found" ]] || die "no paired Apple TV found. Wake the Apple TV and pair it in Xcode."
  fi
  echo "$found"
}

require_signing() {
  local team_file="$PANE_ROOT/local/Signing.local.xcconfig"
  [[ -f "$team_file" ]] || die "local/Signing.local.xcconfig is missing."
  grep -Eq '^PANE_TEAM_ID *= *[A-Z0-9]{10}' "$team_file" \
    || die "PANE_TEAM_ID is not set in local/Signing.local.xcconfig."
}

profile_expiry() {
  local profile="$1/embedded.mobileprovision"
  [[ -f "$profile" ]] || { echo "no embedded.mobileprovision in $(basename "$1")"; return 0; }
  security cms -D -i "$profile" 2>/dev/null | python3 -c '
import datetime
import plistlib
import sys

p = plistlib.loads(sys.stdin.buffer.read())
exp = p["ExpirationDate"]
if exp.tzinfo is None:
    exp = exp.replace(tzinfo=datetime.timezone.utc)
days = (exp - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 86400
print("%s (in %.1f days)" % (exp.astimezone().strftime("%Y-%m-%d %H:%M %Z"), days))
'
}

require_signing
device="$(find_device)"

"$PANE_ROOT/scripts/gen.sh"

echo "== build Pane (Debug, device)"
xcodebuild build \
  -project Pane.xcodeproj \
  -scheme Pane \
  -configuration Debug \
  -destination "platform=tvOS,id=$device" \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -quiet
app="build/DerivedData/Build/Products/Debug-appletvos/Pane.app"
[[ -d "$app" ]] || die "expected build output not found: $app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

echo "== install Pane"
xcrun devicectl device install app --device "$device" "$app" \
  || die "install failed. If the Apple TV is asleep, wake it. If it is unpaired, pair it in Xcode."
echo "== launch Pane"
xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id" \
  || echo "warning: launch failed. If the TV shows an untrusted developer message, trust the developer in Settings." >&2

echo
echo "Pane profile expires: $(profile_expiry "$app")"
