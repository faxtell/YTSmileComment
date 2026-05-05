#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" ]]; then
  echo "[ERROR] THEOS is not set."
  exit 1
fi

command -v make >/dev/null || { echo "[ERROR] make not found"; exit 1; }

# Theos packaging requires `dm.pl` to be visible on PATH. On GitHub Actions,
# Theos may have it under vendor/dm.pl but not expose it as a command.
prepare_dmpl() {
  export PATH="${THEOS}/bin:${THEOS}/vendor/dm.pl:${PATH}"

  if command -v dm.pl >/dev/null 2>&1; then
    echo "[INFO] dm.pl=$(command -v dm.pl)"
    return 0
  fi

  mkdir -p "${THEOS}/bin"

  local candidate=""
  if [[ -f "${THEOS}/vendor/dm.pl/dm.pl" ]]; then
    candidate="${THEOS}/vendor/dm.pl/dm.pl"
  else
    candidate="$(find "${THEOS}" -type f -name 'dm.pl' 2>/dev/null | head -n1 || true)"
  fi

  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    chmod +x "${candidate}" || true
    ln -sf "${candidate}" "${THEOS}/bin/dm.pl"
    export PATH="${THEOS}/bin:${PATH}"
  fi

  if ! command -v dm.pl >/dev/null 2>&1; then
    echo "[ERROR] dm.pl not found. Checked THEOS=${THEOS}"
    echo "[DEBUG] dm.pl candidates:"
    find "${THEOS}" -maxdepth 5 -iname '*dm*' -print 2>/dev/null || true
    exit 1
  fi

  echo "[INFO] dm.pl=$(command -v dm.pl)"
}

prepare_dmpl

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
