import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/player/native/native_player_gating.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 646.1：Windows 启用 MPV 原生 HDR 直出。
///
/// 【真机问题】646 交付后截图显示右上角胶囊是 `libmpv`（= media_kit），
/// 说明原生 UI 未启用。根因有两层：
/// 1. 641 把 Windows 默认引擎改成 media_kit，而原生 UI 门控要求
///    `engine == 'mpv'` → 永不启用；
/// 2. Windows 引擎列表里**根本没有 MPV**（641 移除），设置页也选不到。
///
/// 本轮的完整链路修复：
///   引擎列表加回 MPV → 默认 MPV → 默认视频路径 surface → 门控通过
void main() {
  tearDown(() {
    PlayerEngineFactory.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('① Windows 引擎矩阵（646.1）', () {
    test('681：列表只有 MPV（MDK/Erika 已收敛）', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mpv],
      );
    });

    test('默认引擎 = MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    });

    test('设置页能选到 MPV（tab 由 supportedEngines 生成）', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.supportedEngines().map((e) => e.label),
        contains('MPV'),
      );
    });

    test('旧存档 media_kit 回退到 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mpv,
      );
    });
  });

  group('② Windows 默认视频路径 = surface（原生窗口前提）', () {
    test('未手动设置时返回 surface', () {
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'texture',
          userSet: false,
          platform: TargetPlatform.windows,
        ),
        'surface',
      );
    });

    test('手动设置 texture 时尊重用户（用于排障）', () {
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'texture',
          userSet: true,
          platform: TargetPlatform.windows,
        ),
        'texture',
      );
    });

    test('Android 不受影响（未手动时仍是 surface）', () {
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'surface',
          userSet: false,
          platform: TargetPlatform.android,
        ),
        'surface',
      );
    });
  });

  group('③ 原生 UI 门控全链路（关键）', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Windows + mpv + surface → 启用原生 UI', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.windows,
        ),
        isTrue,
        reason: '646.1 的核心：Windows 走原生顶层窗口 HDR 直出',
      );
    });

    test('Windows + media_kit → 不启用（media_kit 已移除，防御性断言）', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'media_kit',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });

    test('Windows + texture → 不启用（texture 必崩，不应走原生 UI）', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'texture',
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });

    test('Android / 鸿蒙 行为不变', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'ohos',
        ),
        isTrue,
      );
    });
  });

  group('④ 源码守卫', () {
    String read(String p) => File(p).readAsStringSync();

    test('player_engine Windows 分支含 mpv、不含 mediaKit', () {
      final src = read('lib/services/player/player_engine.dart');
      final start = src.indexOf('case TargetPlatform.windows:');
      expect(start, greaterThan(-1));
      final end = src.indexOf('default:', start);
      final block = src.substring(start, end);
      expect(block, contains('PlayerEngine.mpv'));
      expect(block, isNot(contains('PlayerEngine.mediaKit')));
    });

    test('defaultEngine 的 Windows 分支返回 mpv', () {
      final src = read('lib/services/player/player_engine.dart');
      final start = src.indexOf('static PlayerEngine defaultEngine()');
      expect(start, greaterThan(-1));
      final body = src.substring(start);
      final winIdx = body.indexOf('TargetPlatform.windows');
      expect(winIdx, greaterThan(-1));
      final winBlock = body.substring(winIdx);
      expect(winBlock, contains('return PlayerEngine.mpv'));
      expect(winBlock, isNot(contains('return PlayerEngine.mediaKit')));
    });

    test('effectiveMpvVideoOutput 的 Windows 默认返回 surface', () {
      final src = read('lib/models/app_settings.dart');
      final start = src.indexOf('static String effectiveMpvVideoOutput(');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 900);
      final winIdx = body.indexOf('TargetPlatform.windows');
      expect(winIdx, greaterThan(-1));
      final winBlock = body.substring(winIdx, winIdx + 260);
      expect(winBlock, contains("return 'surface'"));
      expect(winBlock, isNot(contains("return 'texture'")));
    });

    test('设置页文案说明 Windows 默认 MPV', () {
      final src = read('lib/screens/settings/player_settings_screen.dart');
      expect(src, contains('Android / Windows / 鸿蒙使用 MPV'));
    });
  });
}
