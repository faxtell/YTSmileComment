#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" ]]; then
  echo "[ERROR] THEOS is not set."
  exit 1
fi

command -v make >/dev/null || { echo "[ERROR] make not found"; exit 1; }

# Theos defaults to `dm.pl` for Debian packaging, but GitHub Actions can fail
# when dm.pl is present as a submodule but not executable/visible to Xcode's make.
# We install dpkg in the workflow, so prefer the real dpkg-deb binary and pass
# its absolute path directly to Theos.
prepare_packager() {
  export PATH="/opt/homebrew/bin:/usr/local/bin:${THEOS}/bin:${THEOS}/vendor/dm.pl:${PATH}"

  local packager=""
  if command -v dpkg-deb >/dev/null 2>&1; then
    packager="$(command -v dpkg-deb)"
  elif command -v dm.pl >/dev/null 2>&1; then
    packager="$(command -v dm.pl)"
  elif [[ -f "${THEOS}/vendor/dm.pl/dm.pl" ]]; then
    packager="${THEOS}/vendor/dm.pl/dm.pl"
    chmod +x "${packager}" || true
  elif [[ -f "${THEOS}/bin/dm.pl" ]]; then
    packager="${THEOS}/bin/dm.pl"
    chmod +x "${packager}" || true
  fi

  if [[ -z "${packager}" || ! -x "${packager}" ]]; then
    echo "[ERROR] No usable deb packager found. Need dpkg-deb or dm.pl."
    echo "[DEBUG] PATH=${PATH}"
    echo "[DEBUG] dpkg-deb candidates:"
    find /opt/homebrew /usr/local -type f -name 'dpkg-deb' -print 2>/dev/null || true
    echo "[DEBUG] dm.pl candidates:"
    find "${THEOS}" -maxdepth 6 -iname 'dm.pl' -print 2>/dev/null || true
    exit 1
  fi

  PACKAGER="${packager}"
  export PACKAGER
  echo "[INFO] deb packager=${PACKAGER}"
}

prepare_packager

echo "[INFO] THEOS=${THEOS}"

# Newer dpkg-deb rejects Theos' historical default compression type `lzma`.
# Force xz in every make invocation so Theos passes `-Zxz` instead of `-Zlzma`.
COMMON_PACKAGE_ARGS=(
  _THEOS_PLATFORM_DPKG_DEB="${PACKAGER}"
  _THEOS_PLATFORM_DPKG_DEB_COMPRESSION=xz
  THEOS_PLATFORM_DEB_COMPRESSION_TYPE=xz
)

make clean "${COMMON_PACKAGE_ARGS[@]}"
make package FINALPACKAGE=1 "${COMMON_PACKAGE_ARGS[@]}"

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
