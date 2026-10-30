import 'dart:convert';
import 'dart:io';

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
      'android/app/src/main/assets/fonts/MaterialIcons-Regular.otf',
      'plugins/himi_mpv_ohos/ohos/src/main/resources/rawfile/'
          'MaterialIcons-Regular.otf',
    ]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 缺失');
      expect(file.lengthSync(), greaterThan(100000),
          reason: '$path 体积异常（可能被占位文件替换）');
    }
  });
}
