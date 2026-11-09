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
    test('Windows 支持 MDK + MPV + Erika，media_kit 已移除', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.mpv,
          PlayerEngine.erika,
        ],
      );
      expect(
        PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mediaKit),
        isFalse,
      );
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

    test('旧存档 mpv / mdk / erika 在 Windows 均保持', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.resolveSelectedEngine('mpv'),
        PlayerEngine.mpv,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.mdk,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('erika'),
        PlayerEngine.erika,
      );
    });

    test('设置页 tab 由 supportedEngines 生成 → Windows 会显示 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final ids =
          PlayerEngineFactory.supportedEngines().map((e) => e.id).toList();
      expect(ids, <String>['mdk', 'mpv', 'erika']);
      expect(ids, contains('mpv'), reason: '设置页引擎 tab 必须有 MPV');
    });
  });

  group('646.1 其他平台不受影响', () {
    test('Android 仍默认 MPV 且含三种引擎', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      expect(PlayerEngineFactory.supportedEngines(), <PlayerEngine>[
        PlayerEngine.mdk,
        PlayerEngine.erika,
        PlayerEngine.mpv,
      ]);
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
    test('player_engine.dart 的 Windows 分支含 MPV 且不含 mediaKit', () {
      final src = File('lib/services/player/player_engine.dart').readAsStringSync();
      final winStart = src.indexOf('case TargetPlatform.windows:');
      expect(winStart, greaterThan(-1));
      final winEnd = src.indexOf('default:', winStart);
      final winBlock = src.substring(winStart, winEnd);
      expect(winBlock, contains('PlayerEngine.mpv'));
      expect(winBlock, contains('PlayerEngine.mdk'));
      expect(winBlock, contains('PlayerEngine.erika'));
      expect(winBlock, isNot(contains('PlayerEngine.mediaKit')));
    });
  });
}
