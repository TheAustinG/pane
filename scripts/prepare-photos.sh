#!/usr/bin/env bash
# Usage: scripts/prepare-photos.sh [--allow-missing] <source-dir> [<out-dir>]
# Turns the source photos into the blurred 1920x1080 HEIC files the app ships. Each source is
# named <slot>.<jpg|jpeg|png|heic|tif> for one of the 28 slots: a condition (clear,
# partlyCloudy, cloudy, rain, storm, snow, fog), a dash and a time (dawn, day, dusk, night),
# for example clear-dawn.jpg. Each is cropped to 16:9 around its center, scaled to 1920x1080,
# blurred with a Gaussian of sigma 12 px and written to <out-dir>/<slot>.heic (default
# App/Photos). Missing slots are listed, and the script fails unless --allow-missing is given.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

use_xcode
need_cmd swift "Install Xcode."

allow_missing=0
positional=()
for arg in "$@"; do
  case "$arg" in
    --allow-missing) allow_missing=1 ;;
    -*) die "unknown option: $arg (see -h)" ;;
    *) positional+=("$arg") ;;
  esac
done
[[ ${#positional[@]} -ge 1 && ${#positional[@]} -le 2 ]] || die "usage: scripts/prepare-photos.sh [--allow-missing] <source-dir> [<out-dir>]"

source_dir="${positional[0]}"
out_dir="${positional[1]:-$PANE_ROOT/App/Photos}"
[[ -d "$source_dir" ]] || die "source directory not found: $source_dir"

conditions=(clear partlyCloudy cloudy rain storm snow fog)
times=(dawn day dusk night)

sources=()
missing=()
for condition in "${conditions[@]}"; do
  for time in "${times[@]}"; do
    slot="$condition-$time"
    found=""
    for extension in jpg jpeg png heic tif; do
      if [[ -f "$source_dir/$slot.$extension" ]]; then
        found="$source_dir/$slot.$extension"
        break
      fi
    done
    if [[ -n "$found" ]]; then sources+=("$found"); else missing+=("$slot"); fi
  done
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "missing ${#missing[@]} of 28 slots: ${missing[*]}" >&2
  [[ $allow_missing -eq 1 ]] || die "add the missing photos or pass --allow-missing"
fi
[[ ${#sources[@]} -gt 0 ]] || die "no photos found in $source_dir"

mkdir -p "$out_dir"
swift "$PANE_ROOT/scripts/blur-photo.swift" "$out_dir" "${sources[@]}"

for source in "${sources[@]}"; do
  name="$(basename "${source%.*}")"
  bytes="$(stat -f %z "$out_dir/$name.heic")"
  echo "$name.heic $((bytes / 1024)) KB"
done
echo "ok: wrote ${#sources[@]} photos to $out_dir"
