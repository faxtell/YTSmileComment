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

DEB_PATH=$(find .theos/packages -name "*.deb" | head -n1)
if [[ -z "${DEB_PATH}" ]]; then
  echo "[ERROR] deb not found"
  exit 1
fi

VERSION=$(awk -F': ' '/^Version:/{print $2}' control)
TARGET_NAME="yt-nico-chat-overlay_${VERSION}_iphoneos-arm64.deb"
cp "$DEB_PATH" ".theos/packages/${TARGET_NAME}"
echo "[OK] deb: $(pwd)/.theos/packages/${TARGET_NAME}"
