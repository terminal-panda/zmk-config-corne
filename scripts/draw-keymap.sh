#!/usr/bin/env bash
# Draw the Corne layout from config/corne.keymap.
#
# Reads the keymap that the firmware actually builds, parses it with
# keymap-drawer, and writes:
#   keymap-drawer/corne.yaml
#   keymap-drawer/corne.svg
#
# Usage:
#   scripts/draw-keymap.sh          # write the files
#   scripts/draw-keymap.sh --open   # write the files and open the SVG
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

open=0
if [[ "${1:-}" == "--open" ]]; then
  open=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: scripts/draw-keymap.sh [--open]" >&2
  exit 2
fi

keymap_file=config/corne.keymap
if [[ ! -f "$keymap_file" ]]; then
  echo "missing $keymap_file" >&2
  exit 1
fi

if ! command -v uvx >/dev/null 2>&1; then
  echo "uvx is required (https://docs.astral.sh/uv/). Install uv, then re-run." >&2
  exit 1
fi

out_dir=keymap-drawer
mkdir -p "$out_dir"
name=$(basename "$keymap_file" .keymap)
yaml="$out_dir/$name.yaml"
svg="$out_dir/$name.svg"

keymap() {
  uvx --from keymap-drawer keymap -c "$out_dir/config.yaml" "$@"
}

keymap parse -z "$keymap_file" -c 12 >"$yaml"
keymap draw "$yaml" >"$svg"

echo "wrote $svg"
echo "source: $keymap_file"

if [[ "$open" -eq 1 ]]; then
  xdg-open "$svg"
fi
