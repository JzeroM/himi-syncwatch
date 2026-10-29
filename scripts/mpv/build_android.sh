#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

ABI="${1:-arm64-v8a}"
case "$ABI" in
  arm64-v8a) BUILD_ARCH=arm64 ;;
  armeabi-v7a) BUILD_ARCH=armv7l ;;
  x86_64) BUILD_ARCH=x86_64 ;;
  *) die "不支持的 Android ABI: $ABI" ;;
esac

for cmd in git unzip zip javac; do require_cmd "$cmd"; done

WORK="$MPV_BUILD_ROOT/android"
SRC="$WORK/mpv-android"
SCRIPTS="$SRC/buildscripts"
OUT="$MPV_OUT_ROOT/android/$ABI"
mkdir -p "$WORK" "$OUT"

log "同步 mpv-android $ANDROID_BUILD_REPO"
clone_at https://github.com/mpv-android/mpv-android "$SRC" "$ANDROID_BUILD_REPO"

export IN_CI=1
# 依赖下载来自 GitHub/dl.google.com：偶发 5xx 会让整个 matrix 失败（曾因
# 单个 ABI 下载 500 挂掉 kernels 作业）。wget 按 tries 重试 5xx/超时。
export WGET="wget --progress=bar:force --tries=10 --waitretry=15 --timeout=60"

log "下载 Android SDK/NDK"
(
  cd "$SCRIPTS"
  ./include/download-sdk.sh
)

log "下载 Android 依赖"
(
  cd "$SCRIPTS"
  ./include/download-deps.sh
)

checkout_ref "$SCRIPTS/deps/ffmpeg" "$ANDROID_FFMPEG"
checkout_ref "$SCRIPTS/deps/mpv" "$ANDROID_MPV_COMMIT"
checkout_ref "$SCRIPTS/deps/libplacebo" "$ANDROID_LIBPLACEBO_COMMIT"
checkout_ref "$SCRIPTS/deps/libass" "$ANDROID_LIBASS_COMMIT"
checkout_ref "$SCRIPTS/deps/dav1d" "$ANDROID_DAV1D_COMMIT"
git -C "$SCRIPTS/deps/libplacebo" submodule update --init --recursive --depth 1

if ! grep -q -- '--cxx=$CXX' "$SCRIPTS/scripts/ffmpeg.sh"; then
  sed -i 's/--cc=$CC --pkg-config=pkg-config/--cc=$CC --cxx=$CXX --pkg-config=pkg-config/' \
    "$SCRIPTS/scripts/ffmpeg.sh"
fi
if ! grep -q -- '--host-cflags' "$SCRIPTS/scripts/ffmpeg.sh"; then
  sed -i 's/--cxx=$CXX/--cxx=$CXX --host-cflags=-march=x86-64 --host-ldflags=-march=x86-64/' \
    "$SCRIPTS/scripts/ffmpeg.sh"
fi

if grep -q -- '-D{lua,libcurl}=enabled' "$SCRIPTS/scripts/mpv.sh"; then
  sed -i 's/-D{lua,libcurl}=enabled/-Dlua=enabled/' "$SCRIPTS/scripts/mpv.sh"
fi

log "应用 Android MediaCodec DoVi 补丁"
if git -C "$SCRIPTS/deps/ffmpeg" apply --check "$SCRIPT_DIR/patches/android-mediacodec-dovi.patch"; then
  git -C "$SCRIPTS/deps/ffmpeg" apply "$SCRIPT_DIR/patches/android-mediacodec-dovi.patch"
elif git -C "$SCRIPTS/deps/ffmpeg" apply --check --reverse "$SCRIPT_DIR/patches/android-mediacodec-dovi.patch"; then
  log "DoVi 补丁已应用"
else
  die "DoVi 补丁无法应用"
fi

log "应用 Android HDR colorspace 补丁"
HDR_PATCH="$SCRIPT_DIR/patches/android-hdr-colorspace.patch"
if git -C "$SCRIPTS/deps/mpv" apply --check "$HDR_PATCH"; then
  git -C "$SCRIPTS/deps/mpv" apply "$HDR_PATCH"
  log "HDR colorspace 补丁已应用"
elif git -C "$SCRIPTS/deps/mpv" apply --check --reverse "$HDR_PATCH"; then
  log "HDR colorspace 补丁已应用"
else
  die "Android HDR colorspace 补丁无法应用"
fi

log "构建 Android 依赖 ($ABI)"
(
  cd "$SCRIPTS"
  ./buildall.sh --only-deps mpv --arch "$BUILD_ARCH"
  ./buildall.sh -n mpv --arch "$BUILD_ARCH"
)

PREFIX="$SCRIPTS/prefix/$BUILD_ARCH"
require_file "$PREFIX/lib/libmpv.so"
# libmpv.so 发布前会被 strip，HDR 符号只在未 strip 的前缀产物中可见。
grep_binary "$PREFIX/lib/libmpv.so" 'vo_android_preferred_csp' || die "libmpv 缺少 Android HDR colorspace 支持"

NDK="$SCRIPTS/sdk/android-ndk-$ANDROID_NDK"
NDK_TOOLCHAIN=$(find "$NDK/toolchains/llvm/prebuilt" -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "$NDK_TOOLCHAIN" ] || die "找不到 Android NDK toolchain"

case "$ABI" in
  arm64-v8a) TRIPLE=aarch64-linux-android ;;
  armeabi-v7a) TRIPLE=arm-linux-androideabi ;;
  x86_64) TRIPLE=x86_64-linux-android ;;
esac
rm -rf "$OUT"/*
cp -f "$PREFIX/lib/libmpv.so" "$OUT/libmpv.so"
shopt -s nullglob
for so in "$PREFIX"/lib/libav*.so* "$PREFIX"/lib/libsw*.so* "$PREFIX"/lib/libpostproc.so* "$PREFIX"/lib/libplacebo.so*; do
  cp -f "$so" "$OUT/"
done
# libmpv 由 NDK r30 构建，必须携带同版本 libc++_shared；fvp 已改为静态 STL。
LIBCXX=$(find "$NDK_TOOLCHAIN/sysroot/usr/lib" -path "*/$TRIPLE/libc++_shared.so" | head -1)
[ -n "$LIBCXX" ] || LIBCXX=$(find "$NDK_TOOLCHAIN" -name 'libc++_shared.so' | head -1)
require_file "$LIBCXX"
cp -f "$LIBCXX" "$OUT/libc++_shared.so"
STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"
[ -x "$STRIP" ] || STRIP=strip
for so in "$OUT"/*.so*; do
  "$STRIP" --strip-unneeded "$so"
done

BASELINE="$WORK/baseline-full-$ABI.jar"
if [ ! -f "$BASELINE" ]; then
  wget -q -O "$BASELINE" \
    "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.8/full-$ABI.jar"
fi
unzip -p "$BASELINE" "lib/$ABI/libmediakitandroidhelper.so" >"$OUT/libmediakitandroidhelper.so"
require_file "$OUT/libmediakitandroidhelper.so"

READELF="$NDK_TOOLCHAIN/bin/llvm-readelf"
[ -x "$READELF" ] || READELF=readelf
machine=$(LC_ALL=C "$READELF" -h "$OUT/libmpv.so" | awk '/Machine:/{print $2}')
case "$ABI:$machine" in
  arm64-v8a:AArch64|armeabi-v7a:ARM|x86_64:Advanced) ;;
  *) die "$ABI 架构校验失败: $machine" ;;
esac
grep_binary "$OUT/libmpv.so" 'mediacodec' || die "libmpv.so 缺少 MediaCodec"
grep_binary "$OUT/libavcodec.so" 'dovi' || die "libavcodec.so 缺少 DoVi"

"$SCRIPT_DIR/package_android_jars.sh" "$OUT" "$ABI" "$MPV_OUT_ROOT/android/jars"
log "Android 内核完成: $ABI"
