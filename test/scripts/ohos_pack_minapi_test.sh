#!/bin/bash
# 697：鸿蒙打包脚本的 minAPIVersion 必须跟随 build-profile.json5
#
# ## 为什么需要这个测试
#
# `scripts/ohos_pack.sh` 是 HAP 的**最终产出方**：它拿 `ohos/template/
# module.json.base` 作模板重新打包，并把 `minAPIVersion` 写进产物。
#
# 此前该字段硬编码 `260000026`（API 26）。即使把 `build-profile.json5`
# 的 `compatibleSdkVersion` 降到 `6.1.1(24)`，重打包后产物里的
# `minAPIVersion` 仍是 26 → 设备侧照样报「应用不匹配当前系统版本」。
#
# 这是个**双层配置**陷阱：改了 build-profile 却没改打包脚本，症状完全
# 一样，极难排查。故用测试钉住「两者必须同源」。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ohos_pack.sh"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     $2"; FAIL=$((FAIL+1)); }

echo "== 鸿蒙打包：minAPIVersion 与 build-profile 同源 =="

[ -f "$SCRIPT" ] || { echo "脚本不存在: $SCRIPT" >&2; exit 1; }

# 语法
if bash -n "$SCRIPT" 2>/dev/null; then ok "语法合法"; else bad "语法错误"; fi

CONTENT="$(cat "$SCRIPT")"

# 不得再硬编码 minAPIVersion（应通过 parse_compatible 动态计算）
if echo "$CONTENT" | grep -qE "app\['minAPIVersion'\] = 260000026"; then
  bad "minAPIVersion 仍硬编码 260000026" "必须从 build-profile 的 compatibleSdkVersion 推导"
else
  ok "minAPIVersion 不再硬编码"
fi

# 必须有解析函数
echo "$CONTENT" | grep -q 'def parse_compatible' && ok "有 parse_compatible 解析" || bad "缺 parse_compatible"
echo "$CONTENT" | grep -q 'def encode_api' && ok "有 encode_api 编码" || bad "缺 encode_api"

# 必须把 build-profile 路径传给 python
echo "$CONTENT" | grep -q 'ohos/build-profile.json5' && ok "传入 build-profile 路径" || bad "未传 build-profile 路径"

# ── 行为验证：编码规则 ──
# hvigor 原生输出反推：6.1.1(24) → 60101024，26.0.0(26) → 260000026
check_encode() {
  local ver="$1" api="$2" expect="$3" desc="$4"
  local got
  got="$(python3 -c "
import sys
def encode_api(ver_str, api):
    parts = [int(x) for x in ver_str.split('.')[:3]]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts
    return int(f'{major}{minor:02d}{patch:02d}{api:03d}')
print(encode_api('$ver', $api))
")"
  if [ "$got" = "$expect" ]; then
    ok "$desc（$ver($api) → $got）"
  else
    bad "$desc" "期望 $expect，实际 $got"
  fi
}

check_encode "6.1.1" 24 "60101024" "API 24 编码"
check_encode "26.0.0" 26 "260000026" "API 26 编码"
check_encode "6.0.0" 20 "60000020" "API 20 编码"

# ── 行为验证：从真实 build-profile 解析 ──
PARSE_RESULT="$(python3 - "$REPO_ROOT/ohos/build-profile.json5" <<'PY'
import json, re, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    text = f.read()
text = re.sub(r'//[^\n]*', '', text)   # 去行注释，避免匹配示例值
m = re.search(r'"compatibleSdkVersion"\s*:\s*"([^"]+)"', text)
if not m:
    print('MISSING')
    sys.exit(0)
raw = m.group(1).strip()
paren = re.search(r'\((\d+)\)', raw)
if paren:
    print(f'{raw[:paren.start()].strip()}|{paren.group(1)}')
else:
    head = raw.split('.')[0]
    print(f'{raw}|{head if head.isdigit() else 26}')
PY
)"

if [ "$PARSE_RESULT" = "MISSING" ]; then
  bad "build-profile 缺 compatibleSdkVersion"
else
  VER="${PARSE_RESULT%|*}"
  API="${PARSE_RESULT#*|}"
  if [ "$API" = "24" ]; then
    ok "当前 compatibleSdkVersion = $VER($API)（覆盖 ≈82.4% 设备）"
  else
    echo "  ℹ️  当前 compatibleSdkVersion = $VER($API)"
    PASS=$((PASS+1))
  fi
fi

echo ""
echo "通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
