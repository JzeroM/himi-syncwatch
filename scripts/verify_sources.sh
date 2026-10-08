#!/usr/bin/env bash
set -uo pipefail

# 打包前校验平台源码完整性。
#
# 背景：CI 的每个 job 都会 rm -rf 整个平台目录再用 flutter create 重建，
# 模板里没有仓库自定义的内容——Android 的 DV Kotlin 插件、HIMI 标签与权限
# 清单，iOS 的图标与显示名。一旦恢复步骤失效，构建照样成功，问题只在真机
# 上以 MissingPluginException 的形式出现，那时已经发版了。这里把「产物与
# 仓库是否一致」变成一条能跑的断言，在 flutter build 之前拦住。
#
# 各 job 只保留自己的平台目录（Android job 会删 ios/，iOS job 会删 android/），
# 因此按目录存在性跳过，缺失的平台不算失败。
#
# 纯文本检查，不依赖 Android SDK / Xcode，本地可直接运行：
#   bash scripts/verify_sources.sh

fail=0
checked=0
ok() { echo "  ✅ $*"; }
err() { echo "  ❌ $*"; fail=1; }
sec() { echo ""; echo "== $* =="; }
skip() { sec "$1"; echo "  ⏭  跳过（无 $2 目录）"; }

# ======================== Android ========================
if [ -d android ]; then
  checked=1
  MAIN=android/app/src/main
  KOTLIN="$MAIN/kotlin/com/himi/syncwatch"
  MANIFEST="$MAIN/AndroidManifest.xml"

  # ---------- 1. DV 插件源码 ----------
  sec "Android · Kotlin 插件"

  if [ -f "$KOTLIN/MainActivity.kt" ]; then
    ok "MainActivity.kt 存在"
  else
    err "缺少 $KOTLIN/MainActivity.kt（flutter create 模板没有它）"
  fi

  if [ -f "$KOTLIN/DolbyVisionPlugin.kt" ]; then
    ok "DolbyVisionPlugin.kt 存在"
  else
    err "缺少 $KOTLIN/DolbyVisionPlugin.kt"
  fi

  if [ -f "$KOTLIN/MainActivity.kt" ]; then
    if grep -q 'DolbyVisionPlugin.CHANNEL' "$KOTLIN/MainActivity.kt"; then
      ok "MainActivity 注册了 com.himi/dolby_vision 通道"
    else
      err "MainActivity 未调用 setMethodCallHandler，DV 探测会 MissingPluginException"
    fi
  fi

  # 只允许仓库那一份 MainActivity：模板实现若并存，绑到哪一个取决于
  # namespace，属于典型的「本地正常、产物失效」。
  extra=$(find "$MAIN/kotlin" -name 'MainActivity.kt' 2>/dev/null \
    | grep -v 'com/himi/syncwatch/MainActivity.kt' || true)
  if [ -n "$extra" ]; then
    err "存在模板生成的多余 MainActivity.kt，会与仓库实现冲突：$extra"
  else
    ok "无模板残留的 MainActivity"
  fi

  # ---------- 2. namespace / applicationId ----------
  sec "Android · Gradle 坐标"

  GRADLE=$(ls android/app/build.gradle android/app/build.gradle.kts 2>/dev/null | head -1 || true)
  if [ -z "$GRADLE" ]; then
    err "找不到 android/app/build.gradle"
  else
    ns=$(grep -Eo 'namespace\s*=\s*"[^"]*"' "$GRADLE" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    if [ "$ns" = "com.himi.syncwatch" ]; then
      ok "namespace = $ns"
    else
      err "namespace = ${ns:-<缺失>}，应为 com.himi.syncwatch（.MainActivity 按此解析）"
    fi

    aid=$(grep -Eo 'applicationId\s*=\s*"[^"]*"' "$GRADLE" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    if [ "$aid" = "com.himi.syncwatch" ]; then
      ok "applicationId = $aid"
    else
      err "applicationId = ${aid:-<缺失>}，应为 com.himi.syncwatch"
    fi
  fi

  # ---------- 3. Manifest ----------
  sec "Android · AndroidManifest"

  if [ -f "$MANIFEST" ]; then
    ok "AndroidManifest.xml 存在"
  else
    err "缺少 $MANIFEST"
  fi

  if [ -f "$MANIFEST" ]; then
    if grep -q 'android:label="HIMI"' "$MANIFEST"; then
      ok 'android:label="HIMI"'
    else
      err '缺少 android:label="HIMI"（应用名会被模板默认值覆盖）'
    fi

    if grep -q 'android:name=".MainActivity"' "$MANIFEST"; then
      ok 'android:name=".MainActivity"'
    else
      err 'manifest 未声明 .MainActivity'
    fi

    # 权限清单必须与仓库保持一致；缺任一条都会削弱产物能力
    # （前台服务权限影响后台播放，存储权限影响旧系统的本地文件选择）。
    perms=(
      android.permission.INTERNET
      android.permission.ACCESS_NETWORK_STATE
      android.permission.RECORD_AUDIO
      android.permission.CAMERA
      android.permission.READ_MEDIA_IMAGES
      android.permission.READ_EXTERNAL_STORAGE
      android.permission.FOREGROUND_SERVICE
      android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK
      android.permission.WAKE_LOCK
    )
    for p in "${perms[@]}"; do
      if grep -q "$p" "$MANIFEST"; then
        ok "$p"
      else
        err "缺少权限 $p"
      fi
    done

    # ---------- 4. 应用图标切换（activity-alias + 插件 Service） ----------
    sec "Android · 应用图标切换"
    for alias in 'DEFAULT' 'icon_artistic' 'icon_glass' 'icon_neon'; do
      if grep -q "android:name=\"\.$alias\"" "$MANIFEST"; then
        ok "activity-alias .$alias"
      else
        err "缺少 activity-alias .$alias（图标切换依赖）"
      fi
    done
    if grep -q 'FlutterDynamicIconPlusService' "$MANIFEST"; then
      ok "FlutterDynamicIconPlusService 已声明"
    else
      err "缺少 flutter_dynamic_icon_plus Service（图标变更不会落地）"
    fi
    for alt in artistic glass neon; do
      f="$MAIN/res/mipmap-xhdpi/ic_launcher_$alt.png"
      if [ -s "$f" ]; then
        ok "备用图标 $alt mipmap 存在"
      else
        err "缺少备用图标 $f（tool/gen_icons.dart 未生成或为空）"
      fi
    done
  fi
else
  skip "Android" "android/"
fi

# ========================== iOS ==========================
if [ -d ios ]; then
  checked=1
  PLIST=ios/Runner/Info.plist
  ASSETS=ios/Runner/Assets.xcassets

  sec "iOS · Info.plist"

  if [ -f "$PLIST" ]; then
    ok "Info.plist 存在"
    if grep -q '<string>HIMI</string>' "$PLIST"; then
      ok 'CFBundleDisplayName = HIMI'
    else
      err '缺少 HIMI 显示名（会被模板默认值覆盖为 himi_syncwatch）'
    fi
    for k in NSMicrophoneUsageDescription NSCameraUsageDescription \
             NSPhotoLibraryUsageDescription NSAppTransportSecurity \
             UIBackgroundModes; do
      if grep -q "<key>$k</key>" "$PLIST"; then
        ok "$k"
      else
        err "Info.plist 缺少 $k"
      fi
    done

    sec "iOS · 备用图标声明"
    if grep -q 'CFBundleAlternateIcons' "$PLIST"; then
      ok "CFBundleAlternateIcons"
    else
      err "Info.plist 缺少 CFBundleAlternateIcons（iOS 图标切换依赖）"
    fi
    for alt in artistic glass neon; do
      if grep -q "<key>$alt</key>" "$PLIST"; then
        ok "备用图标键 $alt"
      else
        err "Info.plist 缺少备用图标键 $alt"
      fi
    done
  else
    err "缺少 $PLIST"
  fi

  # 图标：Contents.json 的 filename 必须都能对上实际文件，且文件非空。
  # 曾出现文件被改名成 .png.img 而引用仍是 .png，引用整体失效、构建却照常
  # 通过；又曾出现文件名正确但内容 0 字节，恢复进 CI 后 Xcode 报
  # "AppIcon did not have any applicable content" 直接失败。两种都要拦。
  sec "iOS · 图标资源"
  if [ -d "$ASSETS" ]; then
    missing=$(python3 - "$ASSETS" <<'PYEOF'
import json, os, sys
root = sys.argv[1]
missing = []
for name in ('AppIcon.appiconset', 'LaunchImage.imageset'):
    d = os.path.join(root, name)
    if not os.path.isdir(d):
        missing.append(f'{name}/ 目录缺失')
        continue
    with open(os.path.join(d, 'Contents.json'), encoding='utf-8') as f:
        data = json.load(f)
    for item in data.get('images', []):
        fn = item.get('filename')
        if not fn:
            continue
        p = os.path.join(d, fn)
        if not os.path.exists(p):
            missing.append(f'{name}/{fn}(缺失)')
        elif os.path.getsize(p) == 0:
            missing.append(f'{name}/{fn}(0字节)')
print('; '.join(missing))
PYEOF
  ) || missing="(解析失败)"
    if [ -z "$missing" ]; then
      ok "Assets.xcassets 引用完整且文件有效（AppIcon + LaunchImage）"
    else
      err "图标资源不可用: $missing"
    fi
  else
    err "缺少 $ASSETS（应用图标会被模板默认图标覆盖）"
  fi
else
  skip "iOS" "ios/"
fi

# ======================== 图标源图 ========================
sec "图标源图（assets/icon）"
for name in default artistic glass neon; do
  src="assets/icon/$name.png"
  if [ -s "$src" ]; then
    ok "$src"
  else
    err "缺少图标源图 $src（flutter_launcher_icons / tool/gen_icons.dart 依赖）"
  fi
done

# ======================== 结果 ========================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "❌ 平台源码校验未通过，产物将与仓库不一致，已中止构建。" >&2
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  echo "❌ 未发现任何平台目录，跳过全部校验（疑似步骤顺序错误）。" >&2
  exit 1
fi
echo "✅ 平台源码校验通过"
