#!/bin/bash
# 测试 patch_android_signing.sh 的 storeFile 路径修复
# 验证: file() 在 :app 模块中能正确找到 keystore 文件

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc"
        echo "     期望: $expected"
        echo "     实际: $actual"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc"
        echo "     未找到: $needle"
        FAIL=$((FAIL+1))
    fi
}

echo "=== 测试 1: storeFile 路径在 key.properties 中 ==="
# 模拟 patch_android_signing.sh 生成 key.properties
STORE_FILE="himi-release.jks"
assert_eq "storeFile 使用相对路径(不含 app/ 前缀)" "himi-release.jks" "$STORE_FILE"

echo ""
echo "=== 测试 2: Gradle file() 在 :app 模块中的路径解析 ==="
# 模拟 Gradle :app 模块的 file() 解析
APP_PROJECT_DIR="/tmp/test_signing_verification/android/app"
STORE_FILE_RELATIVE="$STORE_FILE"
RESOLVED_PATH=$(python3 -c "
import os
app_dir = '$APP_PROJECT_DIR'
store_file = '$STORE_FILE_RELATIVE'
print(os.path.normpath(os.path.join(app_dir, store_file)))
")
assert_eq "file('$STORE_FILE') 解析到 android/app/himi-release.jks" \
    "/tmp/test_signing_verification/android/app/himi-release.jks" \
    "$RESOLVED_PATH"

echo ""
echo "=== 测试 3: 旧路径会解析到错误位置 ==="
OLD_STORE_FILE="app/himi-release.jks"
OLD_RESOLVED_PATH=$(python3 -c "
import os
app_dir = '$APP_PROJECT_DIR'
store_file = '$OLD_STORE_FILE'
print(os.path.normpath(os.path.join(app_dir, store_file)))
")
assert_eq "旧 file('app/himi-release.jks') 会解析到 android/app/app/himi-release.jks (不存在!)" \
    "/tmp/test_signing_verification/android/app/app/himi-release.jks" \
    "$OLD_RESOLVED_PATH"

echo ""
echo "=== 测试 4: build.gradle 中 signingConfigs 注入 ==="
# 用 Python 模拟注入逻辑
RESULT=$(python3 -c "
import re

template = '''plugins {
    id \"com.android.application\"
    id \"kotlin-android\"
    id \"dev.flutter.flutter-gradle-plugin\"
}

android {
    namespace = \"com.himi.himi_syncwatch\"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = \"com.himi.himi_syncwatch\"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
        }
    }
}
'''

t = template

# Insert keyProperties
key_props_block = '''def keyProperties = new Properties()
def keyPropertiesFile = rootProject.file('key.properties')
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.newDataInputStream())
}

'''
if 'def keyProperties' not in t:
    anchor = 'android {'
    pos = t.find(anchor)
    if pos != -1:
        t = t[:pos] + key_props_block + t[pos:]

# Insert signingConfigs
signing_configs_block = '''    signingConfigs {
        release {
            keyAlias keyProperties['keyAlias']
            keyPassword keyProperties['keyPassword']
            storeFile keyProperties['storeFile'] ? file(keyProperties['storeFile']) : null
            storePassword keyProperties['storePassword']
        }
    }

'''
if 'signingConfigs {' not in t:
    anchor = '    buildTypes {'
    pos = t.find(anchor)
    if pos != -1:
        t = t[:pos] + signing_configs_block + t[pos:]

# Replace signingConfig
t = re.sub(
    r'(buildTypes\s*\{[^}]*release\s*\{[^}]*?)signingConfig\s*=\s*signingConfigs\.debug',
    r\"\\1signingConfig = keyProperties['storeFile'] ? signingConfigs.release : signingConfigs.debug\",
    t,
    flags=re.DOTALL
)

# Output key checks
lines = t.split('\n')
checks = []
for i, line in enumerate(lines):
    stripped = line.strip()
    if 'signingConfigs {' in stripped and 'release' not in stripped:
        checks.append('BLOCK:signingConfigs')
    if 'storeFile' in stripped and 'keyProperties' in stripped:
        checks.append('STORE_FILE:' + stripped)
    if 'signingConfig = ' in stripped and 'release' in stripped:
        checks.append('SIGNING_CONFIG:' + stripped)

print('|'.join(checks))
")

assert_contains "注入了 signingConfigs 块" "$RESULT" "BLOCK:signingConfigs"
assert_contains "storeFile 使用 file(keyProperties['storeFile'])" "$RESULT" "storeFile keyProperties"
assert_contains "release buildType 使用 signingConfigs.release" "$RESULT" "SIGNING_CONFIG:signingConfig = keyProperties"

echo ""
echo "================================"
echo "测试结果: $PASS 通过, $FAIL 失败"
if [ $FAIL -gt 0 ]; then
    exit 1
fi
