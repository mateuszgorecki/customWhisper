#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="CustomWhisper"
CONFIGURATION="Release"
APP_NAME="CustomWhisper.app"
BUNDLE_ID="com.customwhisper.CustomWhisper"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/DerivedData"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}"
INSTALL_PATH="/Applications/${APP_NAME}"

echo "==> Generating Xcode project"
cd "${ROOT_DIR}"
xcodegen generate

echo "==> Building ${APP_NAME} (${CONFIGURATION})"
xcodebuild \
  -project "CustomWhisper.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${BUILT_APP_PATH}" ]]; then
  echo "Build succeeded but app was not found at: ${BUILT_APP_PATH}" >&2
  exit 1
fi

if pgrep -x "CustomWhisper" > /dev/null; then
  echo "==> Stopping running app"
  pkill -x "CustomWhisper" || true
  sleep 1
fi

echo "==> Resetting stale TCC entries for accessibility"
tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true

echo "==> Replacing installed app at ${INSTALL_PATH}"
rm -rf "${INSTALL_PATH}"
cp -R "${BUILT_APP_PATH}" "${INSTALL_PATH}"

echo "==> Launching app"
open "${INSTALL_PATH}"

echo "Done. ${APP_NAME} rebuilt and installed."
echo "Note: You may need to re-grant Accessibility permission after rebuild."
