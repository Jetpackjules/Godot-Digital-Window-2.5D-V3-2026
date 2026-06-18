#!/bin/bash
set -euo pipefail

PLUGIN_NAME="iphone_arkit_head_tracker"
TARGET="${1:-release_debug}"
GODOT_VERSION="${2:-4.0}"

if [[ -z "${GODOT_IOS_PLUGINS_REPO:-}" ]]; then
	echo "Set GODOT_IOS_PLUGINS_REPO to a local clone of godot-sdk-integrations/godot-ios-plugins." >&2
	echo "Example:" >&2
	echo "  GODOT_IOS_PLUGINS_REPO=/path/to/godot-ios-plugins $0 release_debug 4.0" >&2
	exit 1
fi

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_PLUGIN_DIR="${GODOT_IOS_PLUGINS_REPO}/plugins/${PLUGIN_NAME}"

mkdir -p "${DEST_PLUGIN_DIR}"
rsync -a --delete \
	--include='*.h' \
	--include='*.mm' \
	--include='*.cpp' \
	--include='*.gdip' \
	--exclude='*' \
	"${PLUGIN_DIR}/" "${DEST_PLUGIN_DIR}/"

cd "${GODOT_IOS_PLUGINS_REPO}"

if ! grep -q "'${PLUGIN_NAME}'" SConstruct; then
	python3 - <<PY
from pathlib import Path
path = Path("SConstruct")
text = path.read_text()
needle = "['', 'apn', 'arkit', 'camera', 'icloud', 'gamecenter', 'inappstore', 'photo_picker']"
replacement = "['', 'apn', 'arkit', 'camera', 'icloud', 'gamecenter', 'inappstore', 'photo_picker', '${PLUGIN_NAME}']"
if needle not in text:
    raise SystemExit("Could not patch SConstruct plugin enum; update it manually.")
path.write_text(text.replace(needle, replacement))
PY
fi

rm -rf "bin/${PLUGIN_NAME}.${TARGET}.xcframework"
./scripts/generate_xcframework.sh "${PLUGIN_NAME}" "${TARGET}" "${GODOT_VERSION}"
rm -rf "${PLUGIN_DIR}/${PLUGIN_NAME}.xcframework"
cp -R "bin/${PLUGIN_NAME}.${TARGET}.xcframework" "${PLUGIN_DIR}/${PLUGIN_NAME}.xcframework"

echo "Built ${PLUGIN_DIR}/${PLUGIN_NAME}.xcframework"
