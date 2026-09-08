#!/usr/bin/env bash
# =============================================================
# 把 media_kit 在 Android 使用的 libmpv 从 "default"（缺 PGS/部分
# 解码器）替换为 media-kit 官方发布的 "full" 完整版。
#
# 原理：media_kit_libs_android_video 在构建期从
#   https://github.com/media-kit/libmpv-android-video-build
# 下载 default-<abi>.jar（内含 libmpv.so）。本脚本在 pub get 之后、
# flutter build 之前，把 pub-cache 里该插件的 build.gradle 下载项
# 改写为 full-<abi>.jar（v1.1.8 起提供 full），并同步替换 MD5。
#
# 用法：在 Android 构建任务中，`flutter pub get` 后调用本脚本。
# =============================================================
set -euo pipefail

# v1.1.8 full-*.jar 的 MD5（media-kit/libmpv-android-video-build）
declare -A FULL_MD5=(
  [arm64-v8a]="d8142f0317695da2b5970b49232a16fe"
  [armeabi-v7a]="78d9b7a5875ab8907542cad8319d1761"
  [x86_64]="be8349d300f2cfaa59670b5b1a0368ce"
  [x86]="2b46056915db8e1aa8a0e79f39071543"
)

# 定位 pub-cache 中的插件 build.gradle（glob 规避版本路径漂移）
BUILD_GRADLE="$(find "$HOME/.pub-cache/hosted/pub.dev" -maxdepth 3 \
  -path '*media_kit_libs_android_video-*/android/build.gradle' 2>/dev/null | head -1 || true)"

if [ -z "${BUILD_GRADLE:-}" ] || [ ! -f "$BUILD_GRADLE" ]; then
  echo "ERROR: 未找到 media_kit_libs_android_video 的 build.gradle"
  exit 1
fi
echo "定位到: $BUILD_GRADLE"

python3 - "$BUILD_GRADLE" <<'PYEOF'
import sys, re
path = sys.argv[1]

# full-*.jar 的 MD5 表（v1.1.8）
full_md5 = {
    "arm64-v8a": "d8142f0317695da2b5970b49232a16fe",
    "armeabi-v7a": "78d9b7a5875ab8907542cad8319d1761",
    "x86_64": "be8349d300f2cfaa59670b5b1a0368ce",
    "x86": "2b46056915db8e1aa8a0e79f39071543",
}

with open(path) as f:
    text = f.read()

changed = False
for abi, md5 in full_md5.items():
    # 1) URL: releases/download/<ver>/default-<abi>.jar -> releases/download/v1.1.8/full-<abi>.jar
    url_pat = re.compile(r'releases/download/[^/"]*/default-' + re.escape(abi) + r'\.jar')
    def url_repl(m):
        return 'releases/download/v1.1.8/full-' + abi + '.jar'
    new_text, n = url_pat.subn(url_repl, text)
    if n:
        text = new_text
        changed = True

    # 2) MD5：定位紧随该 abi url 之后的 "md5": "xxxx"
    idx = text.find('full-' + abi + '.jar')
    if idx == -1:
        continue
    md5_pat = re.compile(r'("md5"\s*:\s*")[0-9a-f]{32}(")')
    m = md5_pat.search(text, idx, idx + 400)
    if m:
        text = text[:m.start(1)] + m.group(1) + md5 + m.group(2) + text[m.end(2):]
        changed = True

if not changed:
    print("WARN: 未发现需要替换的 default 下载项，可能已打过补丁或结构变化")
else:
    with open(path, 'w') as f:
        f.write(text)
    print("已改写为 full-*.jar (v1.1.8) 并更新 MD5")
PYEOF

echo "=== 补丁后校验（应只含 full- 且版本 v1.1.8）==="
grep -o 'releases/download/[^"]*\.jar' "$BUILD_GRADLE"
grep -o '"md5": "[0-9a-f]\{32\}"' "$BUILD_GRADLE"
echo "=== Android full libmpv 补丁完成 ==="
