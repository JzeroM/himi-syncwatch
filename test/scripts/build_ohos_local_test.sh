#!/bin/bash
# 697：鸿蒙本地构建脚本的工具链自举检查
#
# 覆盖三个「报错极不直观」的依赖：
#   1. npm 缺失 → ProcessException: Failed to find "npm"
#   2. java 缺失 → Error Code: 00308018 / spawn java ENOENT
#   3. OHOS_BASE_SDK_HOME 缺失 → ohos_pack.sh 直接退出
#
# 这些都不是功能 bug，但每次新环境都要重新踩一遍，故用测试钉住自举逻辑。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/build_ohos_local.sh"

PASS=0
FAIL=0

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc"
        echo "     缺少: $needle"
        FAIL=$((FAIL+1))
    fi
}

assert_absent() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ❌ $desc"
        echo "     不应出现: $needle"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    fi
}

echo "== 鸿蒙构建脚本工具链自举 =="

[ -f "$SCRIPT" ] || { echo "脚本不存在: $SCRIPT" >&2; exit 1; }

CONTENT="$(cat "$SCRIPT")"

# 语法必须合法
if bash -n "$SCRIPT" 2>/dev/null; then
    echo "  ✅ 语法合法"
    PASS=$((PASS+1))
else
    echo "  ❌ 语法错误"
    FAIL=$((FAIL+1))
fi

# 三个依赖都要有自举探测
assert_contains "自举 npm" "$CONTENT" 'tool/node/bin'
assert_contains "自举 java" "$CONTENT" 'jdk'
assert_contains "自举 SDK 根" "$CONTENT" 'OHOS_BASE_SDK_HOME'

# 自举失败要有可操作提示（而不是让下游抛晦涩错误）
assert_contains "npm 缺失提示" "$CONTENT" '缺少 npm'
assert_contains "java 缺失提示" "$CONTENT" '缺少 java'
assert_contains "SDK 缺失提示" "$CONTENT" '未设置 OHOS_BASE_SDK_HOME'

# 必须尊重用户已配置的环境变量（不能被自举覆盖）
assert_contains "不覆盖已有 JAVA_HOME" "$CONTENT" '[ -z "${JAVA_HOME:-}" ]'
assert_contains "不覆盖已有 SDK 根" "$CONTENT" '[ -z "${OHOS_BASE_SDK_HOME:-}" ]'

# 自举必须发生在 flutter 版本检查之前（否则 npm 报错先炸）
NPM_LINE="$(grep -n 'tool/node/bin' "$SCRIPT" | head -1 | cut -d: -f1)"
FLUTTER_LINE="$(grep -n 'command -v flutter' "$SCRIPT" | head -1 | cut -d: -f1)"
if [ -n "$NPM_LINE" ] && [ -n "$FLUTTER_LINE" ] && [ "$NPM_LINE" -lt "$FLUTTER_LINE" ]; then
    echo "  ✅ 自举在 flutter 检查之前"
    PASS=$((PASS+1))
else
    echo "  ❌ 自举应在 flutter 检查之前（npm=$NPM_LINE flutter=$FLUTTER_LINE）"
    FAIL=$((FAIL+1))
fi

echo ""
echo "通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
