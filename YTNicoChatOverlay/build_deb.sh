#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(awk -F': ' '/^Version:/{print $2}' control)
TARGET_NAME="yt-nico-chat-overlay_${VERSION}_iphoneos-arm64.deb"
OUT_PATH="$(pwd)/.theos/packages/${TARGET_NAME}"
mkdir -p .theos/packages

if [[ -n "${THEOS:-}" && -d "${THEOS}" ]]; then
  command -v make >/dev/null || { echo "[ERROR] make not found"; exit 1; }
  echo "[INFO] THEOS=${THEOS}"
  make clean
  make package FINALPACKAGE=1
  DEB_PATH=$(find .theos/packages -name "*.deb" | head -n1)
  if [[ -z "${DEB_PATH}" ]]; then
    echo "[ERROR] deb not found after Theos build"
    exit 1
  fi
  cp "$DEB_PATH" "$OUT_PATH"
  echo "[OK] deb: ${OUT_PATH}"
  exit 0
fi

echo "[WARN] THEOS is not configured. Building fallback source-only deb package."
PKG_ROOT=".build/fallback_pkg"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/DEBIAN"
mkdir -p "$PKG_ROOT/usr/share/doc/yt-nico-chat-overlay"
mkdir -p "$PKG_ROOT/usr/share/yt-nico-chat-overlay"

cat > "$PKG_ROOT/DEBIAN/control" <<CTL
Package: com.example.yt-nico-chat-overlay
Name: YT Nico Chat Overlay (source-only fallback)
Version: ${VERSION}
Architecture: iphoneos-arm64
Description: Fallback package without compiled tweak binary (THEOS not available)
Maintainer: Local Developer
Author: Local Developer
Section: Tweaks
CTL

cp -a src Makefile control README.md "$PKG_ROOT/usr/share/yt-nico-chat-overlay/"
cat > "$PKG_ROOT/usr/share/doc/yt-nico-chat-overlay/README.FALLBACK" <<DOC
This deb was generated without THEOS, so no compiled MobileSubstrate dylib is included.
Use it only as a transport artifact. For a functional tweak, build on a THEOS-capable environment.
DOC

dpkg-deb -b "$PKG_ROOT" "$OUT_PATH" >/dev/null
echo "[OK] fallback deb: ${OUT_PATH}"
