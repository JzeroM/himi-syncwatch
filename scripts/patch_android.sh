#!/usr/bin/env bash
set -euo pipefail

MANIFEST=android/app/src/main/AndroidManifest.xml

# ===== 1. AndroidManifest：权限 + usesCleartextTraffic =====
python3 - "$MANIFEST" <<'PYEOF'
import sys

manifest = sys.argv[1]
perms = [
    '    <uses-permission android:name="android.permission.INTERNET" />',
    '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
    '    <uses-permission android:name="android.permission.RECORD_AUDIO" />',
    '    <uses-permission android:name="android.permission.WAKE_LOCK" />',
]

with open(manifest, 'r') as f:
    content = f.read()

# 在第一个 <manifest ...> 结束后插入权限
idx = content.find('>')
if idx == -1:
    sys.exit('manifest 根标签格式异常')
insert_at = idx + 1
if '<uses-permission android:name="android.permission.INTERNET"' not in content:
    content = content[:insert_at] + '\n' + '\n'.join(perms) + content[insert_at:]

# 给 <application> 标签补 usesCleartextTraffic
app_idx = content.find('<application')
if app_idx != -1 and 'usesCleartextTraffic' not in content:
    tag_end = content.find('>', app_idx)
    if tag_end != -1:
        attr_insert = app_idx + len('<application')
        content = content[:attr_insert] + ' android:usesCleartextTraffic="true"' + content[attr_insert:]

with open(manifest, 'w') as f:
    f.write(content)

print('manifest 补丁完成')
PYEOF

# ===== 2. 全局 compileSdk / minSdk / 抑制 AAR metadata 检查 =====
python3 - <<'PYEOF'
import os, glob, re

android_dir = 'android'

# gradle.properties
gp = os.path.join(android_dir, 'gradle.properties')
if os.path.exists(gp):
    with open(gp) as f:
        txt = f.read()
    if 'suppressUnsupportedCompileSdk' not in txt:
        txt += '\nandroid.suppressUnsupportedCompileSdk=36\n'
    with open(gp, 'w') as f:
        f.write(txt)
    print('gradle.properties 已更新')

def patch_app_gradle(path):
    with open(path) as f:
        t = f.read()
    changed = False
    # compileSdk / minSdk
    t2 = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36', t)
    if t2 != t:
        t = t2; changed = True
    t2 = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', t)
    if t2 != t:
        t = t2; changed = True
    # 显式关闭 release 的 minify/shrink（Flutter release 默认跑 R8，与 Agora desugar 冲突）
    # 兼容 .kts (isMinifyEnabled = true) 与 .gradle (minifyEnabled true)
    t2 = re.sub(r'isMinifyEnabled\s*=\s*true', 'isMinifyEnabled = false', t)
    if t2 != t: t = t2; changed = True
    t2 = re.sub(r'isShrinkResources\s*=\s*true', 'isShrinkResources = false', t)
    if t2 != t: t = t2; changed = True
    t2 = re.sub(r'minifyEnabled\s+true', 'minifyEnabled false', t)
    if t2 != t: t = t2; changed = True
    t2 = re.sub(r'shrinkResources\s+true', 'shrinkResources false', t)
    if t2 != t: t = t2; changed = True
    with open(path, 'w') as f:
        f.write(t)
    print(f'{path} 已更新: {"changed" if changed else "no-op"}')

for g in glob.glob(os.path.join(android_dir, 'app', 'build.gradle*')):
    patch_app_gradle(g)

PYEOF

echo "=== Android 补丁全部完成 ==="
