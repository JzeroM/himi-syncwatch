import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 646.1：Windows 引擎矩阵改为 MDK + MPV + Erika，默认 MPV。
///
/// 【历史与证据链】
/// - v1.5.3：Windows 默认 MDK → 真机正常；手动切 media_kit → 闪退
/// - 1.5.59 / 1.5.60：用 MPV **texture** 路径 → 闪退
///   （`flutter_windows.dll` 0xc0000005 @ 0x1551f，三次偏移完全一致）
/// - 641：移除 MPV、默认改 media_kit → 仍闪退（同偏移）
/// - 646：实现原生顶层窗口（WS_POPUP + vo=gpu-next HDR 直出），
///   但原生 UI 门控要求 `engine == 'mpv'`，而列表里没有 MPV →
///   永远不启用（真机截图右上角显示 `libmpv` 即为证据）
///
/// 结论：加回 MPV 作为默认（走原生顶层窗口），MDK 保留为备选
/// （Flutter 纹理，不崩但 SDR tone map），media_kit 移除
/// （Flutter 纹理路径在 Windows 上必崩）。
void main() {
  tearDown(() {
    PlayerEngineFactory.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('646.1 Windows 引擎矩阵', () {
    test('681：Windows 仅 MPV（MDK/Erika 已收敛）', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mpv],
      );
      expect(
        PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mediaKit),
        isFalse,
      );
      expect(PlayerEngineFactory.isSingleEngine(), isTrue);
    });

    test('Windows 默认引擎为 MPV（原生 HDR 直出路径）', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isTrue);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mediaKit), isFalse);
    });

    test('旧存档 media_kit 在 Windows 回退到 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mpv,
      );
    });

    test('681：旧存档 mdk / erika 在 Windows 回退到 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.resolveSelectedEngine('mpv'),
        PlayerEngine.mpv,
      );
      // 收敛后 MDK/Erika 不再可用 → 回退 MPV
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.mpv,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('erika'),
        PlayerEngine.mpv,
      );
    });

    test('681：设置页 tab 只有 MPV 一个', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final ids =
          PlayerEngineFactory.supportedEngines().map((e) => e.id).toList();
      expect(ids, <String>['mpv']);
      expect(PlayerEngineFactory.isSingleEngine(), isTrue,
          reason: '单引擎 → 设置页不渲染 TabBar');
    });
  });

  group('646.1 其他平台不受影响', () {
    test('681：Android 手机仅 MPV，TV 保留三引擎', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      // 手机：仅 MPV
      expect(PlayerEngineFactory.supportedEngines(), <PlayerEngine>[
        PlayerEngine.mpv,
      ]);
      expect(PlayerEngineFactory.isSingleEngine(tvMode: false), isTrue);
      // TV：三引擎保留
      expect(PlayerEngineFactory.supportedEngines(tvMode: true), <PlayerEngine>[
        PlayerEngine.mdk,
        PlayerEngine.erika,
        PlayerEngine.mpv,
      ]);
      expect(PlayerEngineFactory.isSingleEngine(tvMode: true), isFalse);
      // 手机老存档 mdk → 回退 mpv
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.mpv,
      );
      // TV 老存档 mdk → 保持
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk', tvMode: true),
        PlayerEngine.mdk,
      );
    });

    test('鸿蒙仍仅 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = true;

      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mpv],
      );
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    });

    test('iOS 仍仅 Erika', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.erika],
      );
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.erika);
    });
  });

  group('646.1 源码守卫', () {
    test('681：Windows 分支只有 MPV', () {
      final src = File('lib/services/player/player_engine.dart').readAsStringSync();
      final winStart = src.indexOf('case TargetPlatform.windows:');
      expect(winStart, greaterThan(-1));
      final winEnd = src.indexOf('default:', winStart);
      final winBlock = src.substring(winStart, winEnd);
      expect(winBlock, contains('PlayerEngine.mpv'));
      // 681：MDK / Erika 已从 Windows 移除
      expect(winBlock, isNot(contains('PlayerEngine.mdk')));
      expect(winBlock, isNot(contains('PlayerEngine.erika')));
      expect(winBlock, isNot(contains('PlayerEngine.mediaKit')));
    });
  });
}
