#!/usr/bin/env bash
set -euo pipefail
unset NODE_OPTIONS

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/ohos/template"
INPUT=""
OUTPUT=""
VERSION_NAME=""
VERSION_CODE=""
SIGNED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --input|-i) INPUT="${2:-}"; shift 2 ;;
    --output|-o) OUTPUT="${2:-}"; shift 2 ;;
    --version-name) VERSION_NAME="${2:-}"; shift 2 ;;
    --version-code) VERSION_CODE="${2:-}"; shift 2 ;;
    --signed) SIGNED=1; shift ;;
    --unsigned) SIGNED=0; shift ;;
    -h|--help)
      echo "用法: $0 --input <unsigned.hap|unsigned.app> --output <out> [--version-name 1.5.1] [--version-code 526] [--signed|--unsigned]"
      echo ""
      echo "  输入 .hap：用 app_packing_tool 重打包（写入版本号）后签名"
      echo "  输入 .app：hvigor assembleApp 产物已是完整包，直接签名"
      exit 0
      ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -f "$INPUT" ] || { echo "输入包不存在: $INPUT" >&2; exit 1; }

# 651：识别输入类型。.app 是 hvigor assembleApp 产出的完整应用包
# （内含各模块 hap + pack.info），版本号在 build-profile.json5 里已定，
# 无需再用 app_packing_tool 重打包 → 直接走签名。
case "$INPUT" in
  *.app) IS_APP=1 ;;
  *)     IS_APP=0 ;;
esac
[ -d "$TEMPLATE" ] || { echo "模板不存在: $TEMPLATE" >&2; exit 1; }
command -v python3 >/dev/null || { echo "缺少 python3" >&2; exit 1; }

SDK_ROOT="${OHOS_BASE_SDK_HOME:-${DEVECO_SDK_HOME:-${HOS_SDK_HOME:-}}}"
[ -n "$SDK_ROOT" ] || { echo "未设置 OHOS_BASE_SDK_HOME / DEVECO_SDK_HOME" >&2; exit 1; }

JAVA_BIN="${OHOS_JAVA_BIN:-${JAVA_HOME:+$JAVA_HOME/bin/java}}"
[ -n "$JAVA_BIN" ] || JAVA_BIN="java"
command -v "$JAVA_BIN" >/dev/null 2>&1 || { echo "Java 不可用: $JAVA_BIN" >&2; exit 1; }

find_tool() {
  local candidate
  for candidate in "$@"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

PACK_TOOL="${OHOS_APP_PACKING_TOOL:-}"
if [ -z "$PACK_TOOL" ]; then
  PACK_TOOL="$(find_tool \
    "$SDK_ROOT/default/openharmony/toolchains/lib/app_packing_tool.jar" \
    "$SDK_ROOT/26/toolchains/lib/app_packing_tool.jar" \
    "$SDK_ROOT/default/hms/toolchains/lib/app_packing_tool.jar" \
    "$SDK_ROOT/toolchains/lib/app_packing_tool.jar")" || true
fi
[ -n "$PACK_TOOL" ] && [ -f "$PACK_TOOL" ] || { echo "找不到 app_packing_tool.jar" >&2; exit 1; }

if [ -z "$VERSION_NAME" ] || [ -z "$VERSION_CODE" ]; then
  LINE="$(grep '^version:' "$ROOT/pubspec.yaml" | head -1)"
  [ -n "$VERSION_NAME" ] || VERSION_NAME="$(printf '%s' "$LINE" | sed -n 's/^version: \([0-9][0-9.]*\).*/\1/p')"
  [ -n "$VERSION_CODE" ] || VERSION_CODE="$(printf '%s' "$LINE" | sed -n 's/.*+\([0-9][0-9]*\).*/\1/p')"
fi
[ -n "$VERSION_NAME" ] && [ -n "$VERSION_CODE" ] || { echo "无法确定版本号" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 651：.app 是 hvigor assembleApp 的容器（内含 entry-default.hap +
# pack.info + pac.json），**没有 libs/resources 等目录结构**，
# 不能用 app_packing_tool 重打包。直接拷贝后签名。
if [ "$IS_APP" = "1" ]; then
  UNSIGNED="$TMP/unsigned.app"
  cp "$INPUT" "$UNSIGNED"
  echo "APP 输入：跳过重打包（版本号来自 build-profile.json5）"
else
WORK="$TMP/work"
mkdir -p "$WORK"
cp -a "$TEMPLATE/ets" "$TEMPLATE/resources" "$TEMPLATE/pkgSdkInfo.json" "$TEMPLATE/resources.index" "$WORK/"
cp "$TEMPLATE/module.json.base" "$WORK/module.json"
cp "$TEMPLATE/pack.info.base" "$WORK/pack.info"

unzip -q "$INPUT" -d "$TMP/new"
rm -rf "$WORK/libs" "$WORK/resources/rawfile/flutter_assets"
cp -a "$TMP/new/libs" "$WORK/libs"
# ArkTS 编译产物必须取自本次 Flutter 构建，而不是 ohos/template 里的旧
# modules.abc：否则插件 Dart 侧更新、原生 ArkTS 仍是旧版（鸿蒙实际
# 输出 texture、HDR 诊断错误即由此产生）。
if [ -f "$TMP/new/ets/modules.abc" ]; then
  rm -rf "$WORK/ets"
  cp -a "$TMP/new/ets" "$WORK/ets"
else
  echo "警告: 输入 HAP 不含 ets/modules.abc，沿用 template 旧 ArkTS" >&2
fi
mkdir -p "$WORK/resources/rawfile"
cp -a "$TMP/new/resources/rawfile/flutter_assets" "$WORK/resources/rawfile/flutter_assets"
if [ -f "$TMP/new/resources/rawfile/buildinfo.json5" ]; then
  cp -a "$TMP/new/resources/rawfile/buildinfo.json5" "$WORK/resources/rawfile/buildinfo.json5"
fi
# 原生播放器控制层的图标字体（ArkUI fontFamily 依赖，EntryAbility 与
# pages/NativePlayer 子窗口页用 $rawfile 注册）。不拷则原生控制层图标全为空框。
if [ -f "$TMP/new/resources/rawfile/MaterialIcons-Regular.otf" ]; then
  cp -a "$TMP/new/resources/rawfile/MaterialIcons-Regular.otf" "$WORK/resources/rawfile/MaterialIcons-Regular.otf"
fi

python3 - "$WORK/module.json" "$WORK/pack.info" "$VERSION_NAME" "$VERSION_CODE" <<'PY'
import json
import sys

module_path, pack_path, version_name, version_code = sys.argv[1:5]
code = int(version_code)

with open(module_path, encoding='utf-8') as f:
    module = json.load(f)
app = module['app']
app['versionName'] = version_name
app['versionCode'] = code
app['vendor'] = 'himi-syncwatch'
app['minAPIVersion'] = 260000026
app['targetAPIVersion'] = 260000026
app['minPatchAPIVersion'] = 0
app['targetPatchAPIVersion'] = 0
app['minMinorAPIVersion'] = 0
app['targetMinorAPIVersion'] = 0
app['compileSdkType'] = 'HarmonyOS'
app['compileSdkVersion'] = '26.0.0.105'
app['apiReleaseType'] = 'Release'
# 652：deviceTypes 与 module.json5 保持一致（phone + tablet）。
# 旧值只写 'phone'，会让 .hap 与 .app 的声明不一致：
# .hap 经此改写为 phone，.app 跳过重打包仍是 hvigor 原值 →
# 云调试侧载 .app 时因设备类型不匹配报「应用版本错误」。
DEVICE_TYPES = ['phone', 'tablet']
module['module']['deviceTypes'] = DEVICE_TYPES
with open(module_path, 'w', encoding='utf-8') as f:
    json.dump(module, f, ensure_ascii=False, separators=(',', ':'))

with open(pack_path, encoding='utf-8') as f:
    pack = json.load(f)
pack['summary']['app']['version'] = {'code': code, 'name': version_name}
for item in pack.get('summary', {}).get('modules', []):
    item['deviceType'] = DEVICE_TYPES
    item.setdefault('apiVersion', {}).update(
        {'compatible': 26, 'releaseType': 'Release', 'target': 26}
    )
for item in pack.get('packages', []):
    item['deviceType'] = DEVICE_TYPES
with open(pack_path, 'w', encoding='utf-8') as f:
    json.dump(pack, f, ensure_ascii=False, separators=(',', ':'))
PY

  UNSIGNED="$TMP/unsigned.hap"
  "$JAVA_BIN" -jar "$PACK_TOOL" --mode hap --force true \
    --lib-path "$WORK/libs" \
    --json-path "$WORK/module.json" \
    --resources-path "$WORK/resources" \
    --index-path "$WORK/resources.index" \
    --pack-info-path "$WORK/pack.info" \
    --ets-path "$WORK/ets" \
    --file-path "$WORK/pkgSdkInfo.json" \
    --out-path "$UNSIGNED" >/tmp/ohos_pack.log 2>&1
fi

mkdir -p "$(dirname "$OUTPUT")"

KIND="HAP"
[ "$IS_APP" = "1" ] && KIND="APP"

if [ "$SIGNED" = "0" ]; then
  cp "$UNSIGNED" "$OUTPUT"
  chmod 600 "$OUTPUT"
  echo "$KIND: $OUTPUT"
  sha256sum "$OUTPUT"
  exit 0
fi

SIGN_DIR="${OHOS_SIGNING_DIR:-$HOME/himi-signing}"
P12="${OHOS_SIGNING_P12:-$SIGN_DIR/himi-release-linux.p12}"
CERT="${OHOS_SIGNING_CERT:-$SIGN_DIR/himi-release-linux.cer}"
PROFILE="${OHOS_SIGNING_PROFILE:-$SIGN_DIR/himi-release-linux.p7b}"
PASSFILE="${OHOS_SIGNING_PASSWORD_FILE:-$SIGN_DIR/.password-linux}"
KEY_ALIAS="${OHOS_SIGNING_KEY_ALIAS:-himi-release}"
for f in "$P12" "$CERT" "$PROFILE" "$PASSFILE"; do
  [ -f "$f" ] || { echo "签名文件不存在: $f" >&2; exit 1; }
done

SIGN_TOOL="${OHOS_SIGN_TOOL:-}"
if [ -z "$SIGN_TOOL" ]; then
  SIGN_TOOL="$(find_tool \
    "$SDK_ROOT/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
    "$SDK_ROOT/26/toolchains/lib/hap-sign-tool.jar" \
    "$SDK_ROOT/default/hms/toolchains/lib/hap-sign-tool.jar" \
    "$SDK_ROOT/toolchains/lib/hap-sign-tool.jar")" || true
fi
[ -n "$SIGN_TOOL" ] && [ -f "$SIGN_TOOL" ] || { echo "找不到 hap-sign-tool.jar" >&2; exit 1; }

PASS="$(cat "$PASSFILE")"
"$JAVA_BIN" -jar "$SIGN_TOOL" sign-app \
  -mode localSign \
  -keyAlias "$KEY_ALIAS" \
  -keyPwd "$PASS" \
  -appCertFile "$CERT" \
  -profileFile "$PROFILE" \
  -keystoreFile "$P12" \
  -keystorePwd "$PASS" \
  -inFile "$UNSIGNED" \
  -signAlg SHA256withECDSA \
  -compatibleVersion 26 \
  -signCode 1 \
  -outFile "$OUTPUT" >/tmp/ohos_sign.log 2>&1
"$JAVA_BIN" -jar "$SIGN_TOOL" verify-app \
  -inFile "$OUTPUT" \
  -outCertChain "$TMP/verify-cert.cer" \
  -outProfile "$TMP/verify-profile.p7b" >/tmp/ohos_verify.log 2>&1
chmod 600 "$OUTPUT"
echo "$KIND: $OUTPUT"
sha256sum "$OUTPUT"
