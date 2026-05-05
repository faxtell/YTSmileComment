#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" ]]; then
  echo "[ERROR] THEOS is not set."
  exit 1
fi

command -v make >/dev/null || { echo "[ERROR] make not found"; exit 1; }

echo "[INFO] THEOS=${THEOS}"
make clean
make package FINALPACKAGE=1

# Depending on the Theos version/configuration, packages may be written to
# ./packages or ./.theos/packages. Prefer the normal ./packages directory but
# support both so CI and local builds behave consistently.
PACKAGE_DIR="packages"
if [[ ! -d "${PACKAGE_DIR}" && -d ".theos/packages" ]]; then
  PACKAGE_DIR=".theos/packages"
fi

DEB_PATH=$(find "${PACKAGE_DIR}" -maxdepth 1 -type f -name "*.deb" | head -n1 || true)
if [[ -z "${DEB_PATH}" ]]; then
  echo "[ERROR] deb not found"
  echo "[DEBUG] Directory listing:"
  find . -maxdepth 3 -type f -name "*.deb" -print || true
  exit 1
fi

VERSION=$(awk -F': ' '/^Version:/{print $2}' control)
TARGET_NAME="yt-nico-chat-overlay_${VERSION}_iphoneos-arm64.deb"
TARGET_PATH="${PACKAGE_DIR}/${TARGET_NAME}"

if [[ "${DEB_PATH}" != "${TARGET_PATH}" ]]; then
  cp "${DEB_PATH}" "${TARGET_PATH}"
fi

echo "[OK] deb: $(pwd)/${TARGET_PATH}"
