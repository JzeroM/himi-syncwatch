#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIP_BREAK_SYSTEM_PACKAGES=1
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_cmd git
require_cmd tar
require_cmd wget
require_cmd curl
require_cmd readelf

WORK="$MPV_BUILD_ROOT/ohos"
SRC="$WORK/libmpv-ohos-build"
OUT="$MPV_OUT_ROOT/ohos"
mkdir -p "$WORK" "$OUT"

log "同步 libmpv-ohos-build"
clone_at https://github.com/mpv-ohos/libmpv-ohos-build "$SRC" "$OHOS_BUILD_REPO"

cat >"$SRC/download/deps-version.sh" <<EOF
#!/bin/bash
set -eu
V_SDK=$OHOS_SDK
V_MBEDTLS=$OHOS_MBEDTLS
V_DAV1D=$OHOS_DAV1D
V_LIBXML2=$OHOS_LIBXML2
V_FRIBIDI=$OHOS_FRIBIDI
V_FREETYPE=$OHOS_FREETYPE
V_HARFBUZZ=$OHOS_HARFBUZZ
V_FONTCONFIG=$OHOS_FONTCONFIG
V_DOVI_TOOLS=$OHOS_DOVI_TOOLS
V_LCMS=$OHOS_LCMS
V_SHADERC=$OHOS_SHADERC
V_FFMPEG=$OHOS_FFMPEG_BRANCH
V_LIBASS=$OHOS_LIBASS
V_LIBPLACEBO=$OHOS_LIBPLACEBO_BRANCH
V_LUA=$OHOS_LUA
V_MPV=$OHOS_MPV_BRANCH
EOF
chmod +x "$SRC/download/deps-version.sh"

SDK_DIR="${OHOS_SDK_DIR:-/sdk}"

ensure_ohos_sdk() {
  local archive="$WORK/ohos-sdk.tar.gz"
  if [ ! -d "$SDK_DIR/linux" ]; then
    if [ ! -f "$archive" ]; then
      log "下载 OpenHarmony SDK $OHOS_SDK"
      wget -q --show-progress -O "$archive" \
        "https://repo.huaweicloud.com/openharmony/os/$OHOS_SDK/ohos-sdk-windows_linux-public.tar.gz"
    fi
  fi
  if [ -w "$(dirname "$SDK_DIR")" ]; then
    mkdir -p "$SDK_DIR"
    tar -C "$SDK_DIR" -zxf "$archive"
    rm -rf "$SDK_DIR/windows"
  else
    sudo mkdir -p "$SDK_DIR"
    sudo tar -C "$SDK_DIR" -zxf "$archive"
    sudo rm -rf "$SDK_DIR/windows"
  fi
  shopt -s nullglob
  for z in "$SDK_DIR/linux"/*.zip; do
    unzip -q -o "$z" -d "$SDK_DIR/linux"
    rm -f "$z"
  done
  shopt -u nullglob
}

ensure_ohos_sdk

sed -i "s|/sdk|$SDK_DIR|g" "$SRC/env.sh" "$SRC/crossfiles/arm64-crossfile-linux.ini"

mkdir -p "$SRC/libmpv/arm64-build"
ln -sf ../crossfiles/arm64-crossfile-linux.ini "$SRC/libmpv/arm64-crossfile.ini"

log "下载 HarmonyOS 依赖"
(
  cd "$SRC"
  ./download/download-deps.sh
)

log "锁定依赖提交"
checkout_ref "$SRC/libmpv/mpv" "$OHOS_MPV"
checkout_ref "$SRC/libmpv/ffmpeg" "$OHOS_FFMPEG"
checkout_ref "$SRC/libmpv/libplacebo" "$OHOS_LIBPLACEBO"

log "准备 Rust OHOS 工具链"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path
fi
export PATH="$HOME/.cargo/bin:$PATH"
rustup target add aarch64-unknown-linux-ohos
if ! command -v cargo-cinstall >/dev/null 2>&1; then
  cargo install cargo-c --features=vendored-openssl
fi

log "应用 HarmonyOS 补丁"
(
  cd "$SRC"
  ./patch.sh
)

log "构建 HarmonyOS libmpv"
(
  cd "$SRC"
  ./build.sh
)

LIBMPV="$SRC/libmpv/arm64-build/libmpv.so"
require_file "$LIBMPV"
cp -f "$LIBMPV" "$OUT/libmpv.so"

machine=$(LC_ALL=C readelf -h "$OUT/libmpv.so" | awk '/Machine:/{print $2}')
[ "$machine" = "AArch64" ] || die "libmpv.so 架构错误: $machine"
grep_binary "$OUT/libmpv.so" 'ohosvk' || die "libmpv.so 缺少 ohosvk"
grep_binary "$OUT/libmpv.so" 'ohcodec_yuv_vk16' || die "libmpv.so 缺少 OHCodec Vulkan 16bit 互操作"
grep_binary "$OUT/libmpv.so" 'DOVI_RPU_BUFFER' || die "libmpv.so 缺少 DoVi RPU side data"

sha256sum "$OUT/libmpv.so" | tee "$OUT/libmpv.so.sha256"
log "HarmonyOS 内核完成: $OUT/libmpv.so"
