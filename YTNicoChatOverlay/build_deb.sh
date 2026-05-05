#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" ]]; then
  echo "[ERROR] THEOS is not set."
  exit 1
fi

command -v make >/dev/null || { echo "[ERROR] make not found"; exit 1; }

# Theos packaging checks the internal `_THEOS_PLATFORM_DPKG_DEB` value.
# Relying only on PATH can fail in GitHub Actions / Xcode make, so resolve dm.pl
# to an absolute path and pass it directly to `make package`.
prepare_dmpl() {
  mkdir -p "${THEOS}/bin"
  export PATH="${THEOS}/bin:${THEOS}/vendor/dm.pl:${PATH}"

  local candidate=""

  if command -v dm.pl >/dev/null 2>&1; then
    candidate="$(command -v dm.pl)"
  elif [[ -f "${THEOS}/bin/dm.pl" ]]; then
    candidate="${THEOS}/bin/dm.pl"
  elif [[ -f "${THEOS}/vendor/dm.pl/dm.pl" ]]; then
    candidate="${THEOS}/vendor/dm.pl/dm.pl"
  else
    candidate="$(find "${THEOS}" -type f -name 'dm.pl' 2>/dev/null | head -n1 || true)"
  fi

  if [[ -z "${candidate}" || ! -f "${candidate}" ]]; then
    echo "[ERROR] dm.pl not found. Checked THEOS=${THEOS}"
    echo "[DEBUG] dm.pl candidates:"
    find "${THEOS}" -maxdepth 6 -iname '*dm*' -print 2>/dev/null || true
    exit 1
  fi

  chmod +x "${candidate}" || true
  ln -sf "${candidate}" "${THEOS}/bin/dm.pl"
  chmod +x "${THEOS}/bin/dm.pl" || true

  DMPL="${THEOS}/bin/dm.pl"
  export DMPL
  echo "[INFO] dm.pl=${DMPL}"
}

prepare_dmpl

echo "[INFO] THEOS=${THEOS}"
make clean _THEOS_PLATFORM_DPKG_DEB="${DMPL}"
make package FINALPACKAGE=1 _THEOS_PLATFORM_DPKG_DEB="${DMPL}"

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
