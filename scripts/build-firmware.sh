#!/usr/bin/env bash
# Build the Corne firmware locally with the same Docker image GitHub Actions uses.
#
# The ZMK/Zephyr checkout lives in ~/.cache/zmk-config-corne/west and is reused,
# so only the first run downloads anything. Firmware lands in firmware/.
#
# Usage:
#   scripts/build-firmware.sh                # build both halves
#   scripts/build-firmware.sh left           # build one half
#   scripts/build-firmware.sh --update       # also pull the ZMK revision in config/west.yml
#   scripts/build-firmware.sh --flash left   # build, then copy to the half when it mounts
#
# To flash: run with --flash, then double-tap the reset button on that half.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
ws=${ZMK_WORKSPACE:-$HOME/.cache/zmk-config-corne/west}
image=zmkfirmware/zmk-build-arm:stable
out=$root/firmware

update=0
flash=0
sides=()
for arg in "$@"; do
  case "$arg" in
    --update) update=1 ;;
    --flash) flash=1 ;;
    left | right) sides+=("$arg") ;;
    *)
      echo "usage: scripts/build-firmware.sh [--update] [--flash] [left|right]" >&2
      exit 2
      ;;
  esac
done
[[ ${#sides[@]} -eq 0 ]] && sides=(left right)

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

mkdir -p "$ws/config" "$out"
cp "$root/config/west.yml" "$ws/config/west.yml"
[[ -d "$ws/zmk" ]] || update=1

run() {
  docker run --rm \
    -v "$root:/repo:ro" -v "$ws:/ws" -w /ws \
    -u "$(id -u):$(id -g)" -e HOME=/ws \
    "$image" bash -c "$1"
}

if [[ "$update" -eq 1 ]]; then
  echo "updating ZMK + Zephyr in $ws"
  if ! run '[ -d .west ] || west init -l config; west update --fetch-opt=--filter=tree:0 && west zephyr-export' \
    >"$ws/update.log" 2>&1; then
    tail -20 "$ws/update.log" >&2
    echo "update failed, full log: $ws/update.log" >&2
    exit 1
  fi
fi

for side in "${sides[@]}"; do
  echo "building $side"
  log=$ws/build-$side.log
  if ! run "west build -p -s zmk/app -d build/$side -b nice_nano//zmk -- \
      -DSHIELD='corne_$side nice_view_adapter nice_view_panda' \
      -DZMK_CONFIG=/repo/config -DZMK_EXTRA_MODULES=/repo" >"$log" 2>&1; then
    grep -E "error|FATAL" "$log" | head -20 >&2
    echo "build failed, full log: $log" >&2
    exit 1
  fi
  cp "$ws/build/$side/zephyr/zmk.uf2" "$out/corne_$side.uf2"
  echo "  firmware/corne_$side.uf2"
done

if [[ "$flash" -eq 1 ]]; then
  for side in "${sides[@]}"; do
    echo "double-tap reset on the $side half..."
    mount=""
    until [[ -n "$mount" ]]; do
      if [[ -e /dev/disk/by-label/NICENANO ]]; then
        mount=$(findmnt -rn -o TARGET -S LABEL=NICENANO 2>/dev/null | head -1 || true)
        [[ -z "$mount" ]] && udisksctl mount -b /dev/disk/by-label/NICENANO >/dev/null 2>&1 || true
      fi
      sleep 1
    done
    cp "$out/corne_$side.uf2" "$mount/"
    sync
    echo "  flashed $side"
    # Wait for the drive to go away before looking for the next half.
    while [[ -e /dev/disk/by-label/NICENANO ]]; do sleep 1; done
  done
fi
