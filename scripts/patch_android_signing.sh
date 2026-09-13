#!/bin/bash
# 为 Android release 构建注入签名配置（注入模式，不覆写 build.gradle）
# 用法: bash scripts/patch_android_signing.sh
# 环境变量: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD

set -euo pipefail

if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "⚠️  ANDROID_KEYSTORE_BASE64 未设置，跳过签名配置（使用 debug 签名）"
  exit 0
fi

echo "🔑 配置 Android APK 签名..."

# 1. 解码 keystore 文件
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/himi-release.jks

# 2. 写入 key.properties
cat > android/app/key.properties << EOF
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=himi-release.jks
EOF

# 3. 注入签名配置到 build.gradle（不覆写，保留 patch_android.sh 的所有修改）
python3 - <<'PYEOF'
import re, glob

for path in glob.glob('android/app/build.gradle'):
    with open(path) as f:
        t = f.read()

    # 3a. 在 plugins 块之后、android 块之前插入 keyProperties 加载代码
    key_props_block = (
        "def keyProperties = new Properties()\n"
        "def keyPropertiesFile = rootProject.file('key.properties')\n"
        "if (keyPropertiesFile.exists()) {\n"
        "    keyProperties.load(keyPropertiesFile.newDataInputStream())\n"
        "}\n\n"
    )
    if 'def keyProperties' not in t:
        # 在 'android {' 之前插入
        anchor = 'android {'
        pos = t.find(anchor)
        if pos != -1:
            t = t[:pos] + key_props_block + t[pos:]

    # 3b. 在 buildTypes 之前插入 signingConfigs 块
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
    if 'signingConfigs' not in t:
        anchor = '    buildTypes {'
        pos = t.find(anchor)
        if pos != -1:
            t = t[:pos] + signing_configs_block + t[pos:]

    # 3c. 替换 release 块中的 signingConfig 行
    t = re.sub(
        r'(buildTypes\s*\{[^}]*release\s*\{[^}]*?)signingConfig\s*=\s*signingConfigs\.debug',
        r'\1signingConfig = keyProperties[\'storeFile\'] ? signingConfigs.release : signingConfigs.debug',
        t,
        flags=re.DOTALL
    )

    with open(path, 'w') as f:
        f.write(t)
    print(f'{path}: 签名配置已注入')

PYEOF

echo "✅ Android 签名配置完成"
echo "   keystore: android/app/himi-release.jks"
echo "   key.properties: android/app/key.properties"
