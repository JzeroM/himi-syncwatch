#!/usr/bin/env bash
set -euo pipefail
unset NODE_OPTIONS

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── 工具链自举（697）──────────────────────────────────────────────
#
# 真机上这三个依赖最容易漏，且报错信息**极不直观**：
#   1. `npm`  —— hvigor 插件安装用；缺失时 Flutter 工具链抛
#      `ProcessException: Failed to find "npm" in the search path`，
#      栈里全是 flutter_tools 内部帧，看不出是 npm 的问题。
#   2. `java` —— hvigor `PackageHap` / `assembleApp` 会 spawn 它做签名；
#      缺失时报 `Error Code: 00308018 Unknown Error / spawn java ENOENT`。
#   3. `OHOS_BASE_SDK_HOME` / `DEVECO_SDK_HOME` —— `ohos_pack.sh` 定位
#      app_packing_tool 与签名工具链。
#
# DevEco 自带的 node/java 默认不在 PATH（尤其从终端启动时），这里自动
# 探测常见安装位置；已有配置则尊重用户环境变量。
HOS_SDK_DEFAULT="$HOME/harmonyos-clt"
if [ -d "$HOS_SDK_DEFAULT" ]; then
  # npm / node
  if ! command -v npm >/dev/null 2>&1 && [ -x "$HOS_SDK_DEFAULT/tool/node/bin/npm" ]; then
    export PATH="$HOS_SDK_DEFAULT/tool/node/bin:$PATH"
  fi
  # java（DevEco 不一定带 JDK，退回常见本地安装）
  if ! command -v java >/dev/null 2>&1; then
    for candidate in "$HOS_SDK_DEFAULT/tool/java/bin" \
                     "$HOME/.local/jdk-17.0.21+9-jre/bin"; do
      if [ -x "$candidate/java" ]; then
        export PATH="$candidate:$PATH"
        [ -z "${JAVA_HOME:-}" ] && export JAVA_HOME="$(dirname "$candidate")"
        break
      fi
    done
  fi
  # SDK 根
  if [ -z "${OHOS_BASE_SDK_HOME:-}" ] && [ -d "$HOS_SDK_DEFAULT/sdk" ]; then
    export OHOS_BASE_SDK_HOME="$HOS_SDK_DEFAULT/sdk"
  fi
  if [ -z "${DEVECO_SDK_HOME:-}" ] && [ -n "${OHOS_BASE_SDK_HOME:-}" ]; then
    export DEVECO_SDK_HOME="$OHOS_BASE_SDK_HOME"
  fi
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter 未找到：请使用 Flutter-OH SDK 的 bin 目录加入 PATH" >&2
  exit 1
fi
if ! flutter --version 2>/dev/null | grep -qi ohos; then
  echo "当前 flutter 不是 Flutter-OH 版本" >&2
  exit 1
fi

# 自举失败时给出可操作的提示，而不是让下游抛晦涩错误。
command -v npm >/dev/null 2>&1 || {
  echo "缺少 npm：hvigor 需要它安装插件。" >&2
  echo "  请把 DevEco 的 node/bin（如 ~/harmonyos-clt/tool/node/bin）加入 PATH" >&2
  exit 1
}
command -v java >/dev/null 2>&1 || {
  echo "缺少 java：hvigor 打包/签名需要 JDK 17+（否则报 spawn java ENOENT）。" >&2
  echo "  请把 JDK 的 bin 目录加入 PATH，或设 JAVA_HOME" >&2
  exit 1
}
[ -n "${OHOS_BASE_SDK_HOME:-}" ] || [ -n "${DEVECO_SDK_HOME:-}" ] || {
  echo "未设置 OHOS_BASE_SDK_HOME / DEVECO_SDK_HOME（指向 HarmonyOS SDK 根）" >&2
  exit 1
}

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

build_hap() {
  flutter build hap --release --no-codesign \
    --dart-define=TRAKT_CLIENT_ID="$TRAKT_CLIENT_ID"
}

# 651：构建 APP 包（应用市场分发包）。
#
# 与 HAP 的区别：HAP 是单模块安装包（设备调试用），APP 是完整应用包
# （含各模块 hap + pack.info，用于 AppGallery / 企业分发）。
#
# 注意：`flutter build hap` 不产出 .app，必须用 hvigor 的 assembleApp，
# 且 **--mode project**（--mode module 会报「任务不存在」）。
# 另需 JAVA 在 PATH，否则报 `spawn java ENOENT`。
build_app() {
  echo "=== 构建 APP 包（hvigor assembleApp）==="
  # assembleApp 内部会 spawn java 做签名/打包；不在 PATH 时报
  # `spawn java ENOENT`（错误信息不直观，这里提前拦截）。
  if ! command -v java >/dev/null 2>&1; then
    echo "java 未在 PATH：hvigor assembleApp 需要 JDK 17+，请把其 bin 目录加入 PATH" >&2
    exit 1
  fi
  (
    cd "$ROOT/ohos"
    hvigorw assembleApp --mode project -p product=default --no-daemon
  )
}

BUILD_LOG="${TMPDIR:-/tmp}/himi-ohos-build.log"
if ! build_hap 2>&1 | tee "$BUILD_LOG"; then
  if grep -qE "has no exported member '(ViewData|AutoFillCallback|FillRequest)'|Property 'requestAutoFill' does not exist" "$BUILD_LOG"; then
    HELPER="$(find ohos/oh_modules/.ohpm -path '*/@ohos/flutter_ohos/src/main/ets/plugin/editing/OhosAutoFillHelper.ets' -print -quit 2>/dev/null || true)"
    if [ -z "$HELPER" ]; then
      echo "检测到 autofill 类型缺失，但未找到 OhosAutoFillHelper.ets" >&2
      exit 1
    fi
    echo "检测到旧 SDK 缺少 autofill 类型，应用兼容补丁后重试..." >&2
    python3 "$ROOT/scripts/ohos_patch_autofill.py" "$HELPER"
    build_hap
  else
    exit 1
  fi
fi

INPUT="build/ohos/hap/entry-default-unsigned.hap"
[ -f "$INPUT" ] || { echo "构建产物不存在: $INPUT" >&2; exit 1; }

# 651：构建 APP 包（在 hap 之后，复用同一次 Flutter 构建的产物）。
build_app
APP_INPUT="ohos/build/outputs/default/ohos-default-unsigned.app"
[ -f "$APP_INPUT" ] || { echo "APP 产物不存在: $APP_INPUT" >&2; exit 1; }

OUT_DIR="$ROOT/dist/ohos/local"
mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d "$OUT_DIR/.staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

sign_one() {
  local input="$1" ext="$2"
  local base="himi-sync-ohos-${VERSION_NAME}-${VERSION_CODE}-local-signed.${ext}"
  local staged="$STAGING/$base"
  "$ROOT/scripts/ohos_pack.sh" \
    --input "$input" \
    --output "$staged" \
    --version-name "$VERSION_NAME" \
    --version-code "$VERSION_CODE" \
    --signed
  find "$OUT_DIR" -maxdepth 1 -type f -name "$base" -delete
  mv "$staged" "$OUT_DIR/$base"
  chmod 600 "$OUT_DIR/$base"
  (
    cd "$OUT_DIR"
    sha256sum "$base" > "$base.sha256"
    chmod 600 "$base.sha256"
  )
  echo "本地包: $OUT_DIR/$base"
  cat "$OUT_DIR/$base.sha256"
}

# 清理旧产物（hap / app / 校验和）
find "$OUT_DIR" -maxdepth 1 -type f \
  \( -name '*-local-signed.hap' -o -name '*-local-signed.app' -o -name '*.sha256' \) -delete

sign_one "$INPUT" hap
sign_one "$APP_INPUT" app
