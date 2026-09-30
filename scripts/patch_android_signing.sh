#!/bin/bash
# 为 Android release 构建注入签名配置（注入模式，不覆写 build.gradle）
# 兼容 Groovy (build.gradle) 与 Kotlin DSL (build.gradle.kts)：
# Flutter 3.29+ 的 flutter create 模板已生成 .kts，只处理 Groovy 会静默漏注，
# 导致 CI 产物退回 runner 的 debug keystore，每次发版签名都不同。
# 用法: bash scripts/patch_android_signing.sh
# 环境变量: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD

set -euo pipefail

if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "❌ ANDROID_KEYSTORE_BASE64 未设置，无法构建正式签名 APK"
  exit 1
fi

# fail fast：两种 DSL 至少要有一个，否则后续注入必然落空
if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  echo "❌ 找不到 android/app/build.gradle 或 build.gradle.kts，无法注入签名配置"
  exit 1
fi

echo "🔑 配置 Android APK 签名..."

# 1. 解码 keystore 文件
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/himi-release.jks

# 2. 写入 key.properties（放在 android/ 根目录，与 rootProject.file('key.properties') 对应）
cat > android/key.properties << EOF
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=himi-release.jks
EOF

# 3. 注入签名配置到 build.gradle / build.gradle.kts（不覆写，保留 patch_android.sh 的所有修改）
python3 - <<'PYEOF'
import re, glob, sys

paths = sorted(glob.glob('android/app/build.gradle*'))
if not paths:
    print('❌ glob 未匹配任何 build.gradle(.kts)', file=sys.stderr)
    sys.exit(1)

for path in paths:
    with open(path) as f:
        t = f.read()
    is_kts = path.endswith('.kts')

    if is_kts:
        # kts 的 import 必须位于文件最顶（plugins 块之前），改用全限定名避免语法错误
        key_props_block = (
            "val keyProperties = java.util.Properties().apply {\n"
            "    val f = rootProject.file(\"key.properties\")\n"
            "    if (f.exists()) f.inputStream().use { load(it) }\n"
            "}\n\n"
        )
        if 'val keyProperties' not in t:
            anchor = 'android {'
            pos = t.find(anchor)
            if pos == -1:
                print(f'❌ {path}: 找不到 android {{ 锚点', file=sys.stderr)
                sys.exit(1)
            t = t[:pos] + key_props_block + t[pos:]

        signing_configs_block = (
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            keyAlias = keyProperties[\"keyAlias\"] as String? ?: \"\"\n"
            "            keyPassword = keyProperties[\"keyPassword\"] as String? ?: \"\"\n"
            "            storeFile = (keyProperties[\"storeFile\"] as String?)?.let { file(it) }\n"
            "            storePassword = keyProperties[\"storePassword\"] as String? ?: \"\"\n"
            "        }\n"
            "    }\n\n"
        )
        if 'signingConfigs {' not in t:
            m = re.search(r'[ \t]*buildTypes\s*\{', t)
            if not m:
                print(f'❌ {path}: 找不到 buildTypes 锚点', file=sys.stderr)
                sys.exit(1)
            pos = m.start()
            t = t[:pos] + signing_configs_block + t[pos:]

        # 模板两种写法都兼容：旧版 signingConfigs.debug、3.29+ kts 的 getByName("debug")
        t, n = re.subn(
            r'(buildTypes\s*\{[^}]*release\s*\{[^}]*?)signingConfig\s*=\s*'
            r'signingConfigs\.(?:getByName\("debug"\)|debug)',
            r'\1signingConfig = if (keyProperties["storeFile"] != null) '
            r'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            t,
            flags=re.DOTALL,
        )
        # n==0 且已含目标引用 → 重复执行（幂等）；否则注入失败
        if n == 0 and 'signingConfigs.getByName("release")' not in t:
            print(f'❌ {path}: release signingConfig 替换失败（模板结构与预期不符）', file=sys.stderr)
            sys.exit(1)
        ok_marker = 'signingConfigs.getByName("release")'
    else:
        key_props_block = (
            "def keyProperties = new Properties()\n"
            "def keyPropertiesFile = rootProject.file('key.properties')\n"
            "if (keyPropertiesFile.exists()) {\n"
            "    keyProperties.load(keyPropertiesFile.newDataInputStream())\n"
            "}\n\n"
        )
        if 'def keyProperties' not in t:
            anchor = 'android {'
            pos = t.find(anchor)
            if pos == -1:
                print(f'❌ {path}: 找不到 android {{ 锚点', file=sys.stderr)
                sys.exit(1)
            t = t[:pos] + key_props_block + t[pos:]

        signing_configs_block = (
            "    signingConfigs {\n"
            "        release {\n"
            "            keyAlias keyProperties['keyAlias']\n"
            "            keyPassword keyProperties['keyPassword']\n"
            "            storeFile keyProperties['storeFile'] ? file(keyProperties['storeFile']) : null\n"
            "            storePassword keyProperties['storePassword']\n"
            "        }\n"
            "    }\n\n"
        )
        if 'signingConfigs {' not in t:
            m = re.search(r'[ \t]*buildTypes\s*\{', t)
            if not m:
                print(f'❌ {path}: 找不到 buildTypes 锚点', file=sys.stderr)
                sys.exit(1)
            pos = m.start()
            t = t[:pos] + signing_configs_block + t[pos:]

        t, n = re.subn(
            r'(buildTypes\s*\{[^}]*release\s*\{[^}]*?)signingConfig\s*=\s*'
            r'signingConfigs\.(?:getByName\("debug"\)|debug)',
            r"\1signingConfig = keyProperties['storeFile'] ? signingConfigs.release : signingConfigs.debug",
            t,
            flags=re.DOTALL,
        )
        if n == 0 and "signingConfigs.release" not in t:
            print(f'❌ {path}: release signingConfig 替换失败（模板结构与预期不符）', file=sys.stderr)
            sys.exit(1)
        ok_marker = 'signingConfigs.release'

    # 注入后自检：必须真的出现 release 签名引用，否则产物会悄悄退回 debug 签名
    if ok_marker not in t:
        print(f'❌ {path}: 注入后自检失败（缺少 {ok_marker}）', file=sys.stderr)
        sys.exit(1)

    with open(path, 'w') as f:
        f.write(t)
    print(f'{path}: 签名配置已注入')

PYEOF

echo "✅ Android 签名配置完成"
echo "   keystore: android/app/himi-release.jks"
echo "   key.properties: android/key.properties"
