#!/bin/bash
# 真实调用 scripts/patch_android_signing.sh 的签名注入测试
# 覆盖：Groovy 注入、Kotlin DSL (.kts) 注入、无 build 文件 fail fast、幂等重跑
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATCH="$REPO_ROOT/scripts/patch_android_signing.sh"

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
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌ $desc"
        echo "     未找到: $needle"
        FAIL=$((FAIL+1))
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ❌ $desc"
        echo "     不应存在: $needle"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ $desc"
        PASS=$((PASS+1))
    fi
}

export ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_BASE64=$(printf 'fake-keystore-bytes' | base64)
export ANDROID_KEYSTORE_PASSWORD=storepw
export ANDROID_KEY_PASSWORD=keypw
export ANDROID_KEY_ALIAS=himi

WORKSPACES=()
WS_DIR=""
# 注意：不能在 $() 里调用（子 shell 会丢 WORKSPACES 累积，临时目录将无法清理）
make_workspace() {
    WS_DIR=$(mktemp -d)
    mkdir -p "$WS_DIR/android/app"
    WORKSPACES+=("$WS_DIR")
}

GROOVY_TEMPLATE='plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace = "com.himi.syncwatch"

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.debug
        }
    }
}
'

# 与 Flutter 3.47.4 真实模板一致：signingConfig 用 getByName("debug") 写法
KTS_TEMPLATE='plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.himi.syncwatch"
    compileSdk = flutter.compileSdkVersion

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'

cleanup() {
    for d in "${WORKSPACES[@]}"; do
        if [ -n "$d" ] && [ -d "$d" ]; then rm -rf "$d"; fi
    done
    return 0
}
trap cleanup EXIT

echo "=== 测试 1: Groovy build.gradle 注入 ==="
make_workspace; ws=$WS_DIR
printf '%s' "$GROOVY_TEMPLATE" > "$ws/android/app/build.gradle"
(cd "$ws" && bash "$PATCH" >/dev/null)
out=$(cat "$ws/android/app/build.gradle")
assert_contains "注入 keyProperties 加载" "$out" "def keyProperties"
assert_contains "注入 release signingConfigs 块" "$out" "signingConfigs {"
assert_contains "release 使用条件签名(有 keystore 走 release)" "$out" "signingConfigs.release"
assert_not_contains "release 不再写死 debug" "$out" "signingConfig = signingConfigs.debug"
keyprops=$(cat "$ws/android/key.properties")
assert_contains "key.properties storeFile 相对路径" "$keyprops" "storeFile=himi-release.jks"
if [ -f "$ws/android/app/himi-release.jks" ]; then
    echo "  ✅ keystore 解码落盘到 android/app/"
    PASS=$((PASS+1))
else
    echo "  ❌ keystore 未生成"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== 测试 2: Kotlin DSL build.gradle.kts 注入（CI 实际场景）==="
make_workspace; ws=$WS_DIR
printf '%s' "$KTS_TEMPLATE" > "$ws/android/app/build.gradle.kts"
(cd "$ws" && bash "$PATCH" >/dev/null)
out=$(cat "$ws/android/app/build.gradle.kts")
assert_contains "注入 val keyProperties（全限定名，不依赖 import 位置）" "$out" "val keyProperties = java.util.Properties()"
assert_contains "注入 create(\"release\") 签名配置" "$out" 'create("release")'
assert_contains "release 使用 getByName 条件签名" "$out" 'signingConfigs.getByName("release")'
assert_contains "保留 debug 回退分支" "$out" 'else signingConfigs.getByName("debug")'
assert_not_contains "不再无条件写死 debug" "$out" 'signingConfig = signingConfigs.getByName("debug")'

echo ""
echo "=== 测试 3: 两种 DSL 同时存在时全部注入 ==="
make_workspace; ws=$WS_DIR
printf '%s' "$GROOVY_TEMPLATE" > "$ws/android/app/build.gradle"
printf '%s' "$KTS_TEMPLATE" > "$ws/android/app/build.gradle.kts"
(cd "$ws" && bash "$PATCH" >/dev/null)
g_out=$(cat "$ws/android/app/build.gradle")
k_out=$(cat "$ws/android/app/build.gradle.kts")
assert_contains "groovy 注入成功" "$g_out" "signingConfigs.release"
assert_contains "kts 注入成功" "$k_out" 'signingConfigs.getByName("release")'

echo ""
echo "=== 测试 4: 重复执行幂等（不重复注入、不报错）==="
(cd "$ws" && bash "$PATCH" >/dev/null)
k_out=$(cat "$ws/android/app/build.gradle.kts")
count=$(echo "$k_out" | grep -cF 'val keyProperties = java.util.Properties()')
assert_eq "keyProperties 只出现一次" "1" "$count"
count=$(echo "$k_out" | grep -cF 'create("release")')
assert_eq "create(\"release\") 只出现一次" "1" "$count"

echo ""
echo "=== 测试 5: 无 build 文件时 fail fast（非 0 退出）==="
make_workspace; ws=$WS_DIR
set +e
(cd "$ws" && bash "$PATCH" >/dev/null 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "  ✅ 退出码非 0（实际 $rc）"
    PASS=$((PASS+1))
else
    echo "  ❌ 无 build 文件时应失败，实际成功了"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== 测试 6: 未设置 ANDROID_KEYSTORE_BASE64 时 fail fast ==="
make_workspace; ws=$WS_DIR
printf '%s' "$KTS_TEMPLATE" > "$ws/android/app/build.gradle.kts"
set +e
(cd "$ws" && env -u ANDROID_KEYSTORE_BASE64 bash "$PATCH" >/dev/null 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "  ✅ 退出码非 0（实际 $rc）"
    PASS=$((PASS+1))
else
    echo "  ❌ 缺少 keystore 环境变量时应失败"
    FAIL=$((FAIL+1))
fi

echo ""
echo "================================"
echo "测试结果: $PASS 通过, $FAIL 失败"
if [ $FAIL -gt 0 ]; then
    exit 1
fi
