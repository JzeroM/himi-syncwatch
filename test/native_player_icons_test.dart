import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_icons.dart';

/// 图标码点单一来源一致性测试。
///
/// 三层校验：
/// 1. `tool/native_icons.json` ↔ Dart [NativePlayerIcons.all]；
/// 2. JSON ↔ Flutter `Icons.xxx.codePoint`（保证与 Flutter 播放页同款图标）；
/// 3. JSON ↔ Android（Kotlin）/ 鸿蒙（ArkTS）图标常量字面量。
void main() {
  final jsonFile = File('tool/native_icons.json');
  final json =
      jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;

  final jsonIcons = (json['icons'] as Map).cast<String, int>();

  test('JSON 与 Dart NativePlayerIcons.all 一致', () {
    expect(jsonIcons, NativePlayerIcons.all);
  });

  test('JSON 与 Flutter Icons 码点一致', () {
    const flutterIcons = <String, IconData>{
      'arrowBack': Icons.arrow_back,
      'speed': Icons.speed,
      'tune': Icons.tune,
      'memory': Icons.memory,
      'rotate': Icons.screen_rotation_alt,
      'fitScreen': Icons.fit_screen,
      'fullscreen': Icons.fullscreen,
      'zoomOutMap': Icons.zoom_out_map,
      'aspectRatio': Icons.aspect_ratio,
      'danmakuOn': Icons.comment,
      'danmakuOff': Icons.comments_disabled,
      'highQuality': Icons.high_quality,
      'subtitles': Icons.subtitles,
      'audioTrack': Icons.audiotrack,
      'playlistPlay': Icons.playlist_play,
      'skipPrevious': Icons.skip_previous,
      'playCircle': Icons.play_circle_fill,
      'pauseCircle': Icons.pause_circle_filled,
      'skipNext': Icons.skip_next,
      'lock': Icons.lock,
      'lockOpen': Icons.lock_open,
      'check': Icons.check,
      'chevronRight': Icons.chevron_right,
      'expandMore': Icons.expand_more,
      'close': Icons.close,
      'campaign': Icons.campaign,
      'people': Icons.people,
      'volumeUp': Icons.volume_up,
      'volumeDown': Icons.volume_down,
      'volumeOff': Icons.volume_off,
      'brightness': Icons.brightness_6,
      'fastForward': Icons.fast_forward,
      'add': Icons.add,
      'delete': Icons.delete_outline,
      'restartAlt': Icons.restart_alt,
      'photoCamera': Icons.photo_camera,
      'bugReport': Icons.bug_report,
      'movie': Icons.movie,
      'search': Icons.search,
      'replay': Icons.replay,
      'forward10': Icons.forward_10,
      'replay10': Icons.replay_10,
      'openInFull': Icons.open_in_full,
      'closeFullscreen': Icons.close_fullscreen,
    };
    expect(flutterIcons.keys.toSet(), jsonIcons.keys.toSet());
    for (final entry in jsonIcons.entries) {
      expect(flutterIcons[entry.key]!.codePoint, entry.value,
          reason: '${entry.key} 码点与 Flutter Icons 不一致');
    }
  });

  test('Android 图标常量包含全部码点', () {
    final source = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerIcons.kt',
    ).readAsStringSync();
    for (final value in jsonIcons.values) {
      expect(source, contains('0x${value.toRadixString(16).toUpperCase()}'),
          reason: 'Android 缺少码点 0x${value.toRadixString(16)}');
    }
  });

  test('鸿蒙图标常量包含全部码点', () {
    final source = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerIcons.ets',
    ).readAsStringSync();
    for (final value in jsonIcons.values) {
      expect(source, contains('0x${value.toRadixString(16).toUpperCase()}'),
          reason: '鸿蒙缺少码点 0x${value.toRadixString(16)}');
    }
  });

  test('两端字体文件已内置', () {
    for (final path in <String>[
      // Android 字体走 res/font（资源 ID 加载），不能放 src/main/assets：
      // assets 会与 Flutter 的 flutter_assets 合并目录冲突，冲突时 Flutter
      // 引擎加载不到资源 → 整个 APK 黑屏（见下方 assets 目录断言）。
      'android/app/src/main/res/font/material_icons.otf',
      // 鸿蒙字体必须放 entry 模块的 rawfile：插件 HAR 的 resources 不会
      // 合并进应用包，只有 entry rawfile 会被打进 HAP（$rawfile 解析到此）。
      'ohos/entry/src/main/resources/rawfile/MaterialIcons-Regular.otf',
    ]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 缺失');
      expect(file.lengthSync(), greaterThan(100000),
          reason: '$path 体积异常（可能被占位文件替换）');
    }
  });

  test('Android 不得预置 src/main/assets（防 APK 黑屏回归）', () {
    // Flutter 构建会把 flutter_assets 写进 android/app/src/main/assets/。
    // 若仓库里预置同名目录及文件，Gradle 资源合并会冲突，导致 Flutter
    // 引擎拿不到 AssetManifest → 整个 APK 黑屏（v1.5.5 真机回归）。
    // Android 侧自有资源一律走 res/（如 res/font），不要放 assets。
    final assets = Directory('android/app/src/main/assets');
    expect(assets.existsSync(), isFalse,
        reason: 'android/app/src/main/assets 不应存在（会与 flutter_assets 合并冲突致 APK 黑屏）');
  });

  test('打包脚本会把鸿蒙字体拷进 HAP', () {
    // ohos_pack.sh 重建 HAP 时按白名单拷贝 rawfile 项；字体漏拷会导致
    // 原生控制层图标全部渲染为空框（EntryAbility 注册失败）。
    final pack = File('scripts/ohos_pack.sh').readAsStringSync();
    expect(pack, contains('MaterialIcons-Regular.otf'),
        reason: 'ohos_pack.sh 未拷贝图标字体到 HAP rawfile');
  });

  test('全部图标码点在两端字体 cmap 中真实存在', () {
    // v1.5.5 真机回归「图标全灭」的防复发：码点在源码里对了，不代表字体里
    // 有对应字形（字体被换/裁剪、码点超出字库范围时控件渲染为空）。
    for (final path in <String>[
      'android/app/src/main/res/font/material_icons.otf',
      'ohos/entry/src/main/resources/rawfile/MaterialIcons-Regular.otf',
    ]) {
      final codepoints = _fontCodepoints(File(path).readAsBytesSync());
      for (final entry in jsonIcons.entries) {
        expect(codepoints.contains(entry.value), isTrue,
            reason:
                '$path 缺少 ${entry.key} 的字形 0x${entry.value.toRadixString(16)}');
      }
    }
  });

  test('图标字体族名唯一且注册链路完整（防 MaterialIcons 族名冲突回归）', () {
    // Flutter 引擎按 FontManifest 注册 'MaterialIcons'（flutter_assets 子集），
    // 自注册字体若同名会被覆盖/冲突，真机表现为图标渲染成空或乱码。
    const family = 'HimiIcons';
    final icons = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerIcons.ets',
    ).readAsStringSync();
    expect(icons, contains("FONT_FAMILY: string = '$family'"),
        reason: '鸿蒙图标字体族名必须为 $family（与 Flutter 占用的 MaterialIcons 隔离）');

    final entry = File('ohos/entry/src/main/ets/entryability/EntryAbility.ets')
        .readAsStringSync();
    expect(entry, contains("const ICON_FONT_FAMILY = '$family'"),
        reason: 'EntryAbility 注册族名与 NativePlayerIcons.FONT_FAMILY 不一致');
    // 现行注册 API：font.registerFont 自 API 18 废弃（旧调用可能静默失效）。
    expect(entry, contains('getFont().registerFont'),
        reason: 'EntryAbility 缺 UIContext.getFont().registerFont 现行注册');
    expect(entry, contains('font.registerFont('),
        reason: 'EntryAbility 应保留 font.registerFont 兼容兜底');

    // 子窗口页面（原生播放 UI 跑在 createSubWindow 子窗口里）：字体注册
    // 作用域是当前窗口的 UIContext，主窗口注册不跨窗口生效——必须在
    // 子窗口页面 aboutToAppear 里再注册（v1.5.5「图标全灭」根因）。
    final page = File('ohos/entry/src/main/ets/pages/NativePlayer.ets')
        .readAsStringSync();
    expect(page, contains('getFont().registerFont'),
        reason: 'NativePlayer 子窗口页缺 UIContext.getFont().registerFont 注册');
    expect(page, contains("ICON_FONT_FAMILY = '$family'"),
        reason: 'NativePlayer 子窗口页注册族名与 NativePlayerIcons.FONT_FAMILY 不一致');

    for (final path in <String>[
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
          'HimiNativePlayerView.ets',
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
          'NativePlayerPanel.ets',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains("'MaterialIcons'"), isFalse,
          reason: '$path 仍引用 Flutter 占用的 MaterialIcons 族名');
      expect(src, contains('NativePlayerIcons.FONT_FAMILY'));
    }
  });

  test('ArkTS 控件层不得内嵌 PUA 裸字形字符（不可见字符维护陷阱）', () {
    // 图标一律走 String.fromCodePoint(...)，裸字符嵌在源码里不可见、
    // 极易引错码点（v1.5.5 曾混入 0xE9B8 野码点）。
    final pua = RegExp(r"Text\('[\u{E000}-\u{F8FF}]'\)", unicode: true);
    for (final path in <String>[
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
          'HimiNativePlayerView.ets',
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
          'NativePlayerPanel.ets',
    ]) {
      final src = File(path).readAsStringSync();
      expect(pua.hasMatch(src), isFalse, reason: '$path 含 PUA 裸字形字面量');
    }
  });
}

/// 解析 sfnt/OTF 的 cmap 表，返回全部已编码码点（支持 format 4/12）。
Set<int> _fontCodepoints(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final numTables = data.getUint16(4);
  final result = <int>{};
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(
      List.generate(4, (k) => data.getUint8(rec + k)),
    );
    if (tag != 'cmap') continue;
    final off = data.getUint32(rec + 8);
    final numSub = data.getUint16(off + 2);
    for (var j = 0; j < numSub; j++) {
      final sub = off + data.getUint32(off + 4 + j * 8 + 4);
      final fmt = data.getUint16(sub);
      if (fmt == 4) {
        final segX2 = data.getUint16(sub + 6);
        final seg = segX2 ~/ 2;
        for (var s = 0; s < seg; s++) {
          final end = data.getUint16(sub + 14 + s * 2);
          final start = data.getUint16(sub + 16 + segX2 + s * 2);
          if (start == 0xFFFF && end == 0xFFFF) continue;
          for (var c = start; c <= end; c++) {
            result.add(c);
          }
        }
      } else if (fmt == 12) {
        final groups = data.getUint32(sub + 12);
        for (var g = 0; g < groups; g++) {
          final start = data.getUint32(sub + 16 + g * 12);
          final end = data.getUint32(sub + 20 + g * 12);
          for (var c = start; c <= end; c++) {
            result.add(c);
          }
        }
      }
    }
    break;
  }
  return result;
}
