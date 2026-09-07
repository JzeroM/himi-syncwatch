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
with open(manifest) as f:
    content = f.read()
idx = content.find('>')
if idx == -1:
    sys.exit('manifest 根标签格式异常')
insert_at = idx + 1
if '<uses-permission android:name="android.permission.INTERNET"' not in content:
    content = content[:insert_at] + '\n' + '\n'.join(perms) + content[insert_at:]
app_idx = content.find('<application')
if app_idx != -1 and 'usesCleartextTraffic' not in content:
    if content.find('>', app_idx) != -1:
        attr_insert = app_idx + len('<application')
        content = content[:attr_insert] + ' android:usesCleartextTraffic="true"' + content[attr_insert:]
with open(manifest, 'w') as f:
    f.write(content)
print('manifest 补丁完成')
PYEOF

# ===== 2. gradle.properties：抑制 metadata + 关 R8 相关 =====
python3 - <<'PYEOF'
import os
gp = 'android/gradle.properties'
if os.path.exists(gp):
    with open(gp) as f:
        txt = f.read()
    add = []
    if 'suppressUnsupportedCompileSdk' not in txt:
        add.append('android.suppressUnsupportedCompileSdk=36')
    if 'android.enableR8.fullMode' not in txt:
        add.append('android.enableR8.fullMode=false')
    if add:
        with open(gp, 'a') as f:
            f.write('\n' + '\n'.join(add) + '\n')
        print('gradle.properties 已追加:', add)
PYEOF

# ===== 3. app 模块：compileSdk/minSdk + release 关闭 minify =====
python3 - <<'PYEOF'
import glob, re

def patch_app(path):
    is_kts = path.endswith('.kts')
    with open(path) as f:
        t = f.read()
    changed = False

    def rep(pat, repl):
        nonlocal t, changed
        t2 = re.sub(pat, repl, t)
        if t2 != t:
            t, changed = t2, True

    # compileSdk / minSdk
    rep(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36')
    rep(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24')
    # 兜底：无论当前值，强制 release 关闭 minify/shrink
    if is_kts:
        rep(r'isMinifyEnabled\s*=\s*true', 'isMinifyEnabled = false')
        rep(r'isShrinkResources\s*=\s*true', 'isShrinkResources = false')
        disable_block = ['isMinifyEnabled = false', 'isShrinkResources = false']
    else:
        rep(r'minifyEnabled\s+true', 'minifyEnabled false')
        rep(r'shrinkResources\s+true', 'shrinkResources false')
        disable_block = ['minifyEnabled false', 'shrinkResources false']

    # 若 release 块中尚无关闭语句，则在 release { 行后插入
    missing = [l for l in disable_block if l not in t]
    if missing and 'release {' in t:
        anchor = 'release {'
        pos = t.find(anchor)
        line_end = t.find('\n', pos)
        if line_end == -1:
            line_end = len(t)
        # 计算 release 行的缩进
        line_start = t.rfind('\n', 0, pos) + 1
        indent = t[line_start:pos]
        inner = '\n' + indent + '    ' + ('\n' + indent + '    ').join(missing)
        t = t[:line_end] + inner + t[line_end:]
        changed = True

    with open(path, 'w') as f:
        f.write(t)
    print(f'{path}: {"已修改" if changed else "no-op"}')

for g in glob.glob('android/app/build.gradle*'):
    patch_app(g)
PYEOF

# ===== 4. 根 build 文件：强制所有 subproject compileSdk 36 并关 minify =====
python3 - <<'PYEOF'
import glob, os
marker = '// [himi] force compileSdk'
target = None
for g in glob.glob('android/build.gradle*'):
    target = g
    break
if not target:
    print('未找到根 build.gradle 文件')
    raise SystemExit(0)

with open(target) as f:
    t = f.read()

if marker in t:
    print('根 build 已包含覆盖，跳过')
else:
    is_kts = target.endswith('.kts')
    if is_kts:
        block = (
            marker + '\n'
            'subprojects {\n'
            '    afterEvaluate {\n'
            '        extensions.findByName("android")?.let {\n'
            '            if (it is com.android.build.gradle.BaseExtension) {\n'
            '                it.compileSdkVersion(36)\n'
            '            } else if (it is com.android.build.gradle.LibraryExtension) {\n'
            '                it.compileSdk = 36\n'
            '            }\n'
            '        }\n'
            '    }\n'
            '}\n'
        )
    else:
        block = (
            marker + '\n'
            'subprojects {\n'
            '    afterEvaluate { project ->\n'
            '        if (project.hasProperty("android")) {\n'
            '            project.android {\n'
            '                compileSdkVersion 36\n'
            '            }\n'
            '        }\n'
            '    }\n'
            '}\n'
        )
    with open(target, 'a') as f:
        f.write('\n' + block)
    print(f'{target}: 已追加 subprojects compileSdk=36 覆盖')

print('=== 根 build.gradle 尾部 ===')
with open(target) as f:
    print(f.read())
PYEOF

echo "=== Android 补丁全部完成 ==="
