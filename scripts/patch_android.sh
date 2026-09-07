#!/usr/bin/env bash
set -euo pipefail

MANIFEST=android/app/src/main/AndroidManifest.xml

# 在 <manifest ...> 结束的 > 之后插入权限
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

# 在第一个 <manifest> 标签整体结束后插入权限
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
        # 找到标签名后的位置，加属性
        attr_insert = app_idx + len('<application')
        content = content[:attr_insert] + ' android:usesCleartextTraffic="true"' + content[attr_insert:]

with open(manifest, 'w') as f:
    f.write(content)

print('manifest 补丁完成')
print(content)
PYEOF

# 更新 compileSdk / minSdk（兼容 .gradle 与 .gradle.kts）
if [ -f android/app/build.gradle.kts ]; then
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/' android/app/build.gradle.kts
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts
  echo "已更新 build.gradle.kts"
else
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/' android/app/build.gradle
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle
  echo "已更新 build.gradle"
fi
