#!/usr/bin/env bash
set -euo pipefail
unset NODE_OPTIONS

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter 未找到：请使用 Flutter-OH SDK 的 bin 目录加入 PATH" >&2
  exit 1
fi
if ! flutter --version 2>/dev/null | grep -qi ohos; then
  echo "当前 flutter 不是 Flutter-OH 版本" >&2
  exit 1
fi

if [ -f "$HOME/.config/himi/trakt.env" ]; then
  set -a
  source "$HOME/.config/himi/trakt.env"
  set +a
fi
if [ -z "${TRAKT_CLIENT_ID:-}" ]; then
  echo "缺少 TRAKT_CLIENT_ID：请先配置 ~/.config/himi/trakt.env" >&2
  exit 1
fi

VERSION_LINE="$(grep '^version:' pubspec.yaml | head -1)"
VERSION_NAME="$(printf '%s' "$VERSION_LINE" | sed -n 's/^version: \([0-9][0-9.]*\).*/\1/p')"
BUILD_NUMBER="$(printf '%s' "$VERSION_LINE" | sed -n 's/.*+\([0-9][0-9]*\).*/\1/p')"
[ -n "$VERSION_NAME" ] && [ -n "$BUILD_NUMBER" ] || { echo "无法解析 pubspec 版本" >&2; exit 1; }
VERSION_CODE="${OHOS_LOCAL_VERSION_CODE:-$BUILD_NUMBER}"

flutter pub get
flutter build hap --release --no-codesign \
  --dart-define=TRAKT_CLIENT_ID="$TRAKT_CLIENT_ID"

INPUT="build/ohos/hap/entry-default-unsigned.hap"
[ -f "$INPUT" ] || { echo "构建产物不存在: $INPUT" >&2; exit 1; }

OUT_DIR="$ROOT/dist/ohos/local"
mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d "$OUT_DIR/.staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BASE="himi-sync-ohos-${VERSION_NAME}-${VERSION_CODE}-local-signed.hap"
STAGED="$STAGING/$BASE"

"$ROOT/scripts/ohos_pack.sh" \
  --input "$INPUT" \
  --output "$STAGED" \
  --version-name "$VERSION_NAME" \
  --version-code "$VERSION_CODE" \
  --signed

find "$OUT_DIR" -maxdepth 1 -type f \
  \( -name '*-local-signed.hap' -o -name '*.sha256' \) -delete
mv "$STAGED" "$OUT_DIR/$BASE"
chmod 600 "$OUT_DIR/$BASE"
(
  cd "$OUT_DIR"
  sha256sum "$BASE" > "$BASE.sha256"
  chmod 600 "$BASE.sha256"
)
echo "本地调试包: $OUT_DIR/$BASE"
cat "$OUT_DIR/$BASE.sha256"
