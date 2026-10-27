#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# mpv-winbuild-cmake 的补丁步骤会在容器内 git commit；Arch 容器默认没有
# user.name/user.email，导致 openssl/spirv-cross patch 以 128 失败。
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-HIMI Build}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-build@himi.local}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-HIMI Build}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-build@himi.local}"

MODE="${1:-all}"
case "$MODE" in
  toolchain|mpv|all) ;;
  *) die "用法: $0 [toolchain|mpv|all]" ;;
esac

for cmd in git cmake ninja python3 file; do require_cmd "$cmd"; done

WORK="$MPV_BUILD_ROOT/windows"
SRC="$WORK/mpv-winbuild-cmake"
BUILD="$WORK/build-x86_64-v3"
OUT="$MPV_OUT_ROOT/windows"
mkdir -p "$WORK" "$OUT"

clone_at https://github.com/shinchiro/mpv-winbuild-cmake "$SRC" "$WINDOWS_MPVBUILD"

python3 - "$SRC/packages/mpv.cmake" "$SRC/packages/ffmpeg.cmake" \
  "$WINDOWS_MPV_COMMIT" "$WINDOWS_FFMPEG_TAG" <<'PY'
import pathlib
import sys

def pin(path, repo, tag):
    p = pathlib.Path(path)
    text = p.read_text()
    head = text.split('ExternalProject_Add_Step')[0]
    if 'GIT_TAG' in head:
        return
    text = text.replace(
        f'    GIT_REPOSITORY {repo}\n',
        f'    GIT_REPOSITORY {repo}\n    GIT_TAG {tag}\n',
        1,
    )
    p.write_text(text)

pin(sys.argv[1], 'https://github.com/mpv-player/mpv.git', sys.argv[3])
pin(sys.argv[2], 'https://github.com/FFmpeg/FFmpeg.git', sys.argv[4])
PY

sed -i '/-Dsubrandr=enabled/d; /-Dlibcurl=enabled/d; s/-Dvapoursynth=enabled/-Dvapoursynth=disabled/' "$SRC/packages/mpv.cmake"
cat >"$SRC/patch_mpv_angle.sh" <<'EOS'
#!/bin/sh
set -e
f=video/out/opengl/context_angle.c
sed -i 's/EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE/EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE/' "$f"
EOS
if ! grep -q 'patch_mpv_angle' "$SRC/packages/mpv.cmake"; then
  sed -i "/GIT_TAG/a\    PATCH_COMMAND \${EXEC} sh $SRC/patch_mpv_angle.sh" \
    "$SRC/packages/mpv.cmake"
fi
sed -i '/^[[:space:]]*curl$/d' "$SRC/packages/mpv.cmake"
sed -i 's/autoupdate -f && //' "$SRC/packages/lame.cmake"
sed -i '/PATCH_COMMAND.*luajit-\*\.patch/d; /PATCH_COMMAND.*mujs-\*\.patch/d' "$SRC/packages/luajit.cmake" "$SRC/packages/mujs.cmake"

if [ ! -f "$BUILD/build.ninja" ]; then
  log "配置 Windows 交叉工具链"
  cmake -G Ninja -S "$SRC" -B "$BUILD" \
    -DTARGET_ARCH=x86_64-w64-mingw32 \
    -DGCC_ARCH="$WINDOWS_GCC_ARCH" \
    -DSINGLE_SOURCE_LOCATION="$WORK/packages"
fi

if [ "$MODE" = "toolchain" ] || [ "$MODE" = "all" ]; then
  log "构建 Windows GCC 工具链"
  ninja -C "$BUILD" gcc
fi

if [ "$MODE" = "mpv" ] || [ "$MODE" = "all" ]; then
  log "构建 Windows libmpv"
  # ExternalProject 用 git 克隆 mpv/FFmpeg（partial clone），CI 偶发网络中断。
  # ninja 会从失败步骤继续，重试不会重复已完成依赖。
  ok=0
  for i in 1 2 3; do
    if ninja -C "$BUILD" mpv; then
      ok=1
      break
    fi
    log "Windows libmpv 构建失败，15 秒后重试（$i/3）"
    sleep 15
  done
  [ "$ok" -eq 1 ] || die "Windows libmpv 构建失败"
  DEV_DIR=$(find "$BUILD" -maxdepth 1 -type d -name "mpv-dev-x86_64-v3-*" | head -1)
  if [ -z "$DEV_DIR" ]; then
    DEV_DIR=$(find "$BUILD" -maxdepth 1 -type d -name "mpv-dev-x86_64-*" | head -1)
  fi
  [ -n "$DEV_DIR" ] || die "找不到 mpv-dev 输出目录"
  rm -rf "$OUT"/*
  require_file "$DEV_DIR/libmpv-2.dll"
  require_file "$DEV_DIR/libmpv.dll.a"
  cp -f "$DEV_DIR/libmpv-2.dll" "$OUT/"
  cp -f "$DEV_DIR/libmpv.dll.a" "$OUT/"
  mkdir -p "$OUT/include/mpv"
  cp -f "$DEV_DIR/include/mpv/"*.h "$OUT/include/mpv/"
  file "$OUT/libmpv-2.dll" | grep -q 'PE32+' || die "libmpv-2.dll 不是 64 位 PE"
  sha256sum "$OUT/libmpv-2.dll" "$OUT/libmpv.dll.a" | tee "$OUT/SHA256SUMS"
  log "Windows 内核完成: $OUT/libmpv-2.dll"
fi
