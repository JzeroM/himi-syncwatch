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

# 【697 真机根因】mpv-android 上游不构建 shaderc —— 因为它把 libplacebo 的
# Vulkan 关掉了（`-Dvulkan=disabled`），从不需要 SPIR-V 编译器。我们打开了
# Vulkan，就必须补上：libplacebo `src/glsl/spirv.c` 的 `pl_spirv_create()`
# 在既无 shaderc 又无 glslang 时直接返回 NULL 并打
# `Failed initializing any SPIR-V compiler!`，随后 `pl_gpu_create_vk()`
# 失败 → mpv 报 `Failed initializing any suitable GPU context!` → 回落 GL。
#
# 证据：我们旧 APK 的 libmpv.so 里 `Initialized SPIR-V compiler` 出现 0 次
# （该 slog 在编译器数组为空时被编译期消除），而带 Vulkan 可用的构建是 1 次。
log "同步 shaderc（libplacebo Vulkan 的 SPIR-V 编译器）"
if [ ! -d "$SCRIPTS/deps/shaderc/.git" ]; then
  git clone --depth 1 --branch "$ANDROID_SHADERC" \
    https://github.com/google/shaderc "$SCRIPTS/deps/shaderc"
fi
checkout_ref "$SCRIPTS/deps/shaderc" "$ANDROID_SHADERC"
# shaderc v2025.x 起依赖不再用 git submodule，而是 DEPS + utils/git-sync-deps
# （glslang / spirv-tools / spirv-headers 都在 third_party/ 下）
if [ -f "$SCRIPTS/deps/shaderc/utils/git-sync-deps" ]; then
  ( cd "$SCRIPTS/deps/shaderc" && python3 utils/git-sync-deps )
else
  git -C "$SCRIPTS/deps/shaderc" submodule update --init --recursive --depth 1
fi
[ -f "$SCRIPTS/deps/shaderc/third_party/glslang/CMakeLists.txt" ] \
  || die "shaderc 依赖没同步全（缺 third_party/glslang）"

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

log "为 Vulkan 创建 pkg-config 文件（仅头文件，不链接）"
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
# 【必须链接 -lvulkan】mpv 的 Vulkan context 直接调用
# vkCreateAndroidSurfaceKHR / vkGetInstanceProcAddr 等符号。
# 不给 -lvulkan 会留下未定义符号 → System.loadLibrary 用 RTLD_NOW
# 解析失败 → 白屏（media_kit 插件静态块里 loadLibrary("mpv")）。
#
# 【VK_KHR_display 是桌面扩展，Android 永远没有】即使 API 35 的 NDK
# stub 也缺这 5 个符号。用 --defsym 把它们定义成绝对地址 0，让链接器
# 视为已定义 → RTLD_NOW 不再报错。mpv 只在检测到该扩展时才调用它们，
# Android 上永不触发，所以不会跳到 0。
Libs: -L${libdir} -lvulkan \
  -Wl,--defsym=vkCreateDisplayPlaneSurfaceKHR=0 \
  -Wl,--defsym=vkGetDisplayModePropertiesKHR=0 \
  -Wl,--defsym=vkGetDisplayPlaneSupportedDisplaysKHR=0 \
  -Wl,--defsym=vkGetPhysicalDeviceDisplayPlanePropertiesKHR=0 \
  -Wl,--defsym=vkGetPhysicalDeviceDisplayPropertiesKHR=0
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
# 【libvulkan.so 链接 stub】mpv 的 Vulkan context 直接调用
# vkGetInstanceProcAddr / vkCreateAndroidSurfaceKHR 等 13 个符号，
# 必须链接 libvulkan 才能解析（否则 System.loadLibrary 用 RTLD_NOW
# 解析失败 → 白屏）。
#
# NDK 的 stub 按 API level 分目录，只有 API 24+ 才有（Vulkan 1.0 从
# API 24 引入），而编译用 API 23 → 需要把 24+ 的 stub 拷到 prefix/lib。
VULKAN_STUB=""
for _api in 36 35 34 33 32 31 30 29 28 27 26 25 24; do
  _cand="$VULKAN_SYSROOT/usr/lib/$VULKAN_TRIPLE/$_api/libvulkan.so"
  if [ -f "$_cand" ]; then VULKAN_STUB="$_cand"; break; fi
done
[ -z "$VULKAN_STUB" ] && [ -f "$VULKAN_SYSROOT/usr/lib/$VULKAN_TRIPLE/libvulkan.so" ] \
  && VULKAN_STUB="$VULKAN_SYSROOT/usr/lib/$VULKAN_TRIPLE/libvulkan.so"
if [ -n "$VULKAN_STUB" ]; then
  cp -f "$VULKAN_STUB" "$PREFIX_DIR/lib/libvulkan.so"
  log "libvulkan.so stub 已拷贝: $VULKAN_STUB"
else
  log "NDK 无 libvulkan.so stub，自建空 stub（仅满足链接，运行时由系统 loader 提供）"
  VULKAN_CLANG="$VULKAN_SYSROOT/../bin/clang"
  [ -x "$VULKAN_CLANG" ] || die "找不到 NDK clang: $VULKAN_CLANG"
  echo 'void _himi_vulkan_stub(void) {}' | \
    "$VULKAN_CLANG" --target=${VULKAN_TRIPLE}23 --sysroot="$VULKAN_SYSROOT" \
      -shared -x c - -o "$PREFIX_DIR/lib/libvulkan.so" \
      -Wl,-soname,libvulkan.so
fi

log "vulkan.pc 已创建: $PREFIX_DIR/lib/pkgconfig/vulkan.pc"

log "写入 buildscripts/scripts/shaderc.sh"
cat > "$SCRIPTS/scripts/shaderc.sh" <<'SHADERC_SCRIPT'
#!/bin/bash -e

# 697：shaderc 静态构建（Android NDK）。
#
# mpv-android 上游没有这个依赖，因为它的 libplacebo 关着 Vulkan。我们开了
# Vulkan，就必须提供 GLSL→SPIR-V 编译器，否则 Vulkan 上下文起不来。
#
# 参考 mpv-ohos/libmpv-ohos-build 的同名脚本（那边 Vulkan 一直是好的）：
# CMake + Ninja、静态、跳过测试/示例/命令行工具，最后把 `shaderc_combined.pc`
# 改名成 `shaderc.pc`——libplacebo 的 meson 用 `dependency('shaderc')`，
# 而 shaderc 默认生成的 `shaderc.pc` 指向动态库 `-lshaderc_shared`。

. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf "$build"
	exit 0
else
	exit 255
fi

# NDK 的 ABI 名与 mpv-android 的 arch 名不同，按 triple 映射
case "$ndk_triple" in
	aarch64-*) android_abi=arm64-v8a ;;
	arm-*)     android_abi=armeabi-v7a ;;
	i686-*)    android_abi=x86 ;;
	x86_64-*)  android_abi=x86_64 ;;
	*) echo "未知 ndk_triple: $ndk_triple" >&2; exit 1 ;;
esac

mkdir -p "$build"
cd "$build"

cmake -GNinja \
	-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
	-DANDROID_ABI="$android_abi" \
	-DANDROID_PLATFORM=android-23 \
	-DANDROID_STL=c++_shared \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr/local \
	-DCMAKE_SKIP_RPATH=TRUE \
	-DBUILD_SHARED_LIBS=OFF \
	-DSHADERC_SKIP_TESTS=ON \
	-DSHADERC_SKIP_EXAMPLES=ON \
	-DSHADERC_SKIP_EXECUTABLES=ON \
	-DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
	-DSHADERC_ENABLE_WERROR_COMPILE=OFF \
	..

ninja -j"$cores"
# 【必须用 DESTDIR 而不是把 prefix 指到 $prefix_dir】shaderc 的 .pc 模板是
#   prefix=@CMAKE_INSTALL_PREFIX@
# 而 buildall 会给 pkg-config 设 PKG_CONFIG_SYSROOT_DIR=$prefix_dir：若 .pc 里
# 写的已经是 $prefix_dir 绝对路径，就会被二次前缀成
# `$prefix_dir/$prefix_dir/...` → 头文件/库全部找不到。
# 与其它 meson 依赖一致，写成 /usr/local，再靠 setup_prefix 建的
# usr→. / local→. 软链落到平铺前缀。
DESTDIR="$prefix_dir" ninja install

pcdir="$prefix_dir/usr/local/lib/pkgconfig"
[ -d "$pcdir" ] || pcdir="$prefix_dir/lib/pkgconfig"
[ -f "$pcdir/shaderc_combined.pc" ] || {
	echo "shaderc_combined.pc 缺失，静态构建异常" >&2
	exit 1
}
# 静态库只有 shaderc_combined；把 shaderc.pc 让给 combined，供 meson 使用
mv -f "$pcdir/shaderc.pc" "$pcdir/shaderc_shared.pc" 2>/dev/null || true
cp -f "$pcdir/shaderc_combined.pc" "$pcdir/shaderc.pc"
SHADERC_SCRIPT
chmod +x "$SCRIPTS/scripts/shaderc.sh"

# buildall.sh 只会构建 depinfo.sh 里声明为依赖的目录，且要求 deps/<name> 存在
if grep -q '^dep_libplacebo=()$' "$SCRIPTS/include/depinfo.sh"; then
  sed -i 's/^dep_libplacebo=()$/dep_shaderc=()\ndep_libplacebo=(shaderc)/' \
    "$SCRIPTS/include/depinfo.sh"
fi
grep -q '^dep_libplacebo=(shaderc)$' "$SCRIPTS/include/depinfo.sh" \
  || die "depinfo.sh 结构已变，shaderc 依赖注入失败"

log "启用 libplacebo Vulkan + shaderc（SPIR-V 编译器是 Vulkan 的硬依赖）"
if grep -q -- '-Dvulkan=disabled' "$SCRIPTS/scripts/libplacebo.sh"; then
  sed -i 's/-Dvulkan=disabled/-Dvulkan=enabled -Dshaderc=enabled/' \
    "$SCRIPTS/scripts/libplacebo.sh"
elif ! grep -q -- '-Dshaderc=enabled' "$SCRIPTS/scripts/libplacebo.sh"; then
  sed -i 's/-Dvulkan=enabled/-Dvulkan=enabled -Dshaderc=enabled/' \
    "$SCRIPTS/scripts/libplacebo.sh"
fi
grep -q -- '-Dvulkan=enabled' "$SCRIPTS/scripts/libplacebo.sh" \
  || die "libplacebo.sh 结构已变，Vulkan patch 需要更新"
grep -q -- '-Dshaderc=enabled' "$SCRIPTS/scripts/libplacebo.sh" \
  || die "libplacebo.sh 未启用 shaderc（Vulkan 会静默回落 OpenGL）"

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
grep_binary "$PREFIX/lib/libmpv.so" 'pl_gpu_create_vk' || die "libmpv 缺少 Vulkan 后端（DV compute shader 不可用）"
# 【必须有】SPIR-V 编译器：`Initialized SPIR-V compiler '%s'` 只在
# compilers[] 非空时才会生成（数组为空时整段循环是死代码，字符串会被
# 编译器消除）。这条断言能挡住「有 Vulkan 后端但起不来」的假成功——
# 697 真机就是这么静默回落 OpenGL 的。
grep_binary "$PREFIX/lib/libmpv.so" 'Initialized SPIR-V compiler' \
  || die "libmpv 缺少 SPIR-V 编译器（shaderc 未链接）→ Vulkan 上下文必然初始化失败"
grep_binary "$PREFIX/lib/libmpv.so" 'shaderc_compile_into_spv' \
  || die "libmpv 缺少 shaderc_compile_into_spv（shaderc 未静态链接）"

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
