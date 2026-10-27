#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ $# -eq 3 ] || die "用法: $0 <so-dir> <abi> <out-dir>"
SO_DIR=$1
ABI=$2
OUT_DIR=$3
[ -d "$SO_DIR" ] || die "so 目录不存在: $SO_DIR"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

shopt -s nullglob
SO_FILES=("$SO_DIR"/*.so*)
[ ${#SO_FILES[@]} -gt 0 ] || die "没有 .so: $SO_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib/$ABI"
for so in "${SO_FILES[@]}"; do
  cp -f "$so" "$TMP/lib/$ABI/"
done

JAR="$OUT_DIR/full-$ABI.jar"
rm -f "$JAR"
(
  cd "$TMP"
  zip -q -r "$JAR" lib
)
unzip -l "$JAR" | grep -q "lib/$ABI/libmpv.so" || die "jar 缺少 libmpv.so"
unzip -l "$JAR" | grep -q "lib/$ABI/libavcodec.so" || die "jar 缺少 libavcodec.so"
unzip -l "$JAR" | grep -q "lib/$ABI/libmediakitandroidhelper.so" || die "jar 缺少 libmediakitandroidhelper.so"
sha256sum "$JAR" | tee "$JAR.sha256"
log "Android jar: $JAR"
