#!/bin/bash
# 为 Android release 构建注入签名配置
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

# 3. 覆写 build.gradle，加入签名配置
cat > android/app/build.gradle << 'GRADLE'
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def keyProperties = new Properties()
def keyPropertiesFile = rootProject.file('key.properties')
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.newDataInputStream())
}

android {
    namespace = "com.himi.syncwatch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "com.himi.syncwatch"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        release {
            keyAlias keyProperties['keyAlias']
            keyPassword keyProperties['keyPassword']
            storeFile keyProperties['storeFile'] ? file(keyProperties['storeFile']) : null
            storePassword keyProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig = keyProperties['storeFile'] ? signingConfigs.release : signingConfigs.debug
        }
    }
}

flutter {
    source = "../.."
}
GRADLE

echo "✅ Android 签名配置完成"
echo "   keystore: android/app/himi-release.jks"
echo "   key.properties: android/app/key.properties"
