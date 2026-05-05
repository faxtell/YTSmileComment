#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
THEOS_DIR="${THEOS:-$ROOT_DIR/theos}"

if [[ ! -d "$THEOS_DIR" ]]; then
  git clone --depth 1 https://github.com/theos/theos.git "$THEOS_DIR"
else
  echo "[INFO] THEOS already exists: $THEOS_DIR"
fi

mkdir -p "$THEOS_DIR/sdks"
SDK_PATH="$THEOS_DIR/sdks/iPhoneOS16.5.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  curl -L https://github.com/theos/sdks/archive/refs/heads/master.tar.gz -o /tmp/theos-sdks.tar.gz
  tar -xzf /tmp/theos-sdks.tar.gz -C /tmp
  cp -R /tmp/sdks-master/iPhoneOS16.5.sdk "$SDK_PATH"
fi

echo "THEOS=$THEOS_DIR" >> "$GITHUB_ENV"
echo "[OK] THEOS prepared at $THEOS_DIR"
