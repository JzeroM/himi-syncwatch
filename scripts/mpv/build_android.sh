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

NDK="$SCRIPTS/sdk/android-ndk-$ANDROID_NDK"

log "为 Vulkan 创建 pkg-config 文件（NDK sysroot 自带头文件和 stub）"
# 【为什么需要】meson 交叉编译时 `dependency('vulkan')` 只走 pkg-config，
# 不走编译器探测。NDK sysroot 自带 Vulkan 头文件和 libvulkan.so stub，
# 但没有 vulkan.pc → meson 报 `vulkan found: NO`。
VULKAN_SYSROOT="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
[ -d "$VULKAN_SYSROOT/usr/include/vulkan" ] \
  || die "NDK 缺少 Vulkan 头文件: $VULKAN_SYSROOT/usr/include/vulkan"
# 【必须先建目录+符号链接】buildall.sh 只在 prefix_dir 不存在时创建
# `usr -> .` 和 `local -> .` 符号链接（PKG_CONFIG_SYSROOT_DIR 依赖它们
# 解析 /usr/include 路径）。如果先 mkdir 导致目录已存在，buildall.sh
# 会跳过符号链接创建 → 后续 pkg-config 路径全错。
PREFIX_DIR="$SCRIPTS/prefix/$BUILD_ARCH"
if [ ! -d "$PREFIX_DIR" ]; then
  mkdir -p "$PREFIX_DIR"
  ln -s . "$PREFIX_DIR/usr"
  ln -s . "$PREFIX_DIR/local"
fi
mkdir -p "$PREFIX_DIR/lib/pkgconfig"
cat > "$PREFIX_DIR/lib/pkgconfig/vulkan.pc" <<'VULKANPC'
prefix=/usr
includedir=${prefix}/include
libdir=${prefix}/lib

Name: Vulkan
Description: Vulkan Graphics API (NDK sysroot stub)
Version: 1.3.238
Cflags: -I${includedir}
Libs: -lvulkan
VULKANPC

# 【关键】NDK 的 libvulkan.so stub 在 `usr/lib/<triple>/`（无版本号目录），
# 但编译器用 API 23 → 链接器只搜 `<triple>/23/` → 找不到 libvulkan。
# 拷到 prefix/lib 让 `-lvulkan` 能找到（`-L$prefix_dir/usr/local/lib`
# 在链接命令里已存在）。
case "$BUILD_ARCH" in
  arm64)   VULKAN_TRIPLE=aarch64-linux-android ;;
  armv7l)  VULKAN_TRIPLE=arm-linux-androideabi ;;
  x86_64)  VULKAN_TRIPLE=x86_64-linux-android ;;
  *)       die "未知架构: $BUILD_ARCH" ;;
esac
# 【NDK r30 不自带 libvulkan.so】只有 Vulkan 头文件，没有链接 stub。
# 运行时由 Android 系统的 Vulkan loader 提供实现，构建时只需要一个
# 空的 shared library 满足 `-lvulkan` 链接即可。
VULKAN_CLANG="$VULKAN_SYSROOT/../bin/clang"
[ -x "$VULKAN_CLANG" ] || die "找不到 NDK clang: $VULKAN_CLANG"
# 【必须带 API level + sysroot】否则找不到 crtbegin_so.o / crtend_so.o
# （NDK 的 CRT 文件按 API level 分目录）。
echo 'void _himi_vulkan_stub(void) {}' | \
  "$VULKAN_CLANG" --target=${VULKAN_TRIPLE}23 --sysroot="$VULKAN_SYSROOT" \
    -shared -x c - -o "$PREFIX_DIR/lib/libvulkan.so" \
    -Wl,-soname,libvulkan.so
log "libvulkan.so stub 已创建: $PREFIX_DIR/lib/libvulkan.so"

log "vulkan.pc 已创建: $PREFIX_DIR/lib/pkgconfig/vulkan.pc"

log "启用 libplacebo Vulkan（DV 元数据处理需要 compute shader）"
if ! grep -q -- '-Dvulkan=disabled' "$SCRIPTS/scripts/libplacebo.sh"; then
  die "libplacebo.sh 结构已变，Vulkan patch 需要更新"
fi
sed -i 's/-Dvulkan=disabled/-Dvulkan=enabled/' "$SCRIPTS/scripts/libplacebo.sh"

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
# libplacebo 是静态库（default_library=static），符号在 libmpv.so 里
grep_binary "$PREFIX/lib/libmpv.so" 'pl_gpu_vk' || die "libmpv 缺少 Vulkan 后端（DV compute shader 不可用）"

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
