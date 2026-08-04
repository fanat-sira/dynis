#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/dynis-build}"
MODULE_DIR="$BUILD_DIR/DynisBackend"

if ! command -v quickshell >/dev/null 2>&1; then
    echo "quickshell is not in PATH." >&2
    echo "Install or rebuild Quickshell first, then rerun this script." >&2
    exit 1
fi

if [[ ! -f "$BUILD_DIR/qmldir" || ! -f "$BUILD_DIR/libDynisBackendplugin.so" || ! -f "$BUILD_DIR/libDynisBackend.so" ]]; then
    echo "Build artifacts are missing in $BUILD_DIR." >&2
    echo "Run: cmake -S \"$REPO_DIR\" -B \"$BUILD_DIR\" && cmake --build \"$BUILD_DIR\" -j2" >&2
    exit 1
fi

mkdir -p "$MODULE_DIR"
ln -sf "$BUILD_DIR/qmldir" "$MODULE_DIR/qmldir"
ln -sf "$BUILD_DIR/DynisBackend.qmltypes" "$MODULE_DIR/DynisBackend.qmltypes"
ln -sf "$BUILD_DIR/libDynisBackendplugin.so" "$MODULE_DIR/libDynisBackendplugin.so"

export QML2_IMPORT_PATH="$BUILD_DIR${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export LD_LIBRARY_PATH="$BUILD_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec quickshell -p "$REPO_DIR"
