#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT_SOURCE_DIR="$SCRIPT_DIR/../fonts"
FONT_DESTINATION="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/dynis"

if [[ ! -d "$FONT_SOURCE_DIR" ]]; then
    echo "Dynis font assets are missing: $FONT_SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$FONT_DESTINATION"
find "$FONT_SOURCE_DIR" -type f -name '*.ttf' -exec install -m 0644 -t "$FONT_DESTINATION" {} +

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$FONT_DESTINATION"
fi

echo "Installed Dynis fonts to $FONT_DESTINATION"
