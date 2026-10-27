#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LC_ALL=C
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

ROOT="${1:-$MPV_OUT_ROOT}"
TARGET="${2:-all}"
failed=0

ok() { printf 'OK   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; failed=1; }

check_ohos() {
  local so="$ROOT/ohos/libmpv.so"
  [ -f "$so" ] || { bad "缺少 $so"; return; }
  readelf -h "$so" | grep -q 'AArch64' && ok "OHOS AArch64" || bad "OHOS 架构"
  for s in ohosvk hwdec_ohcodec_pl ohcodec_yuv_vk16 DOVI_RPU_BUFFER libplacebo; do
    grep -aq "$s" "$so" && ok "OHOS $s" || bad "OHOS 缺少 $s"
  done
}

check_android() {
  local dir="$ROOT/android"
  [ -d "$dir" ] || { bad "缺少 $dir"; return; }
  local found=0
  for so in "$dir"/*/libmpv.so; do
    [ -f "$so" ] || continue
    found=1
    readelf -h "$so" | grep -qE 'AArch64|ARM|X86-64' && ok "Android $(basename "$(dirname "$so")")" || bad "Android 架构 $so"
    grep -aq 'mediacodec' "$so" && ok "Android MediaCodec $so" || bad "Android MediaCodec $so"
    local codec
    codec=$(dirname "$so")/libavcodec.so
    [ -f "$codec" ] || { bad "缺少 $codec"; continue; }
    grep -aq 'MediaCodec DoVi RPU' "$codec" && ok "Android DoVi $codec" || bad "Android DoVi $codec"
  done
  [ "$found" -eq 1 ] || bad "没有 Android libmpv.so"
}

check_windows() {
  local dll="$ROOT/windows/libmpv-2.dll"
  [ -f "$dll" ] || { bad "缺少 $dll"; return; }
  file "$dll" | grep -q 'PE32+' && ok "Windows PE32+" || bad "Windows 架构"
  grep -aq 'mpv_create' "$dll" && ok "Windows mpv_create" || bad "Windows 导出"
  grep -aq 'apply_dolbyvision' "$dll" && ok "Windows DoVi 滤镜" || bad "Windows DoVi 滤镜"
  grep -aq 'libplacebo' "$dll" && ok "Windows libplacebo" || bad "Windows libplacebo"
}

case "$TARGET" in
  all) check_ohos; check_android; check_windows ;;
  ohos) check_ohos ;;
  android) check_android ;;
  windows) check_windows ;;
  *) die "未知目标: $TARGET" ;;
esac
exit "$failed"
