import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 641：Windows 从 MPV 改为默认 media_kit，并移除 MPV 选项。
///
/// 真机回归（1.5.59.639，`himi_syncwatch.exe`）：
/// - texture 路径：从播放页返回时崩在 `flutter_windows.dll`
///   （0xc0000005 @ 0x1551f，`ValueListenableBuilder` 与 textureId
///   notifier 的生命周期竞态）；
/// - surface 路径：原生子 HWND 被 Flutter 不透明窗口遮挡 → 灰屏。
///
/// 故 Windows 改用 media_kit（Flutter 纹理，长期验证稳定），
/// MDK 保留为备选，MPV 从可选列表移除。
void main() {
  tearDown(() {
    PlayerEngineFactory.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('641 Windows 引擎矩阵', () {
    test('Windows 支持 MDK + media_kit + Erika，不再支持 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final engines = PlayerEngineFactory.supportedEngines();
      expect(engines, <PlayerEngine>[
        PlayerEngine.mdk,
        PlayerEngine.mediaKit,
        PlayerEngine.erika,
      ]);
      expect(engines, isNot(contains(PlayerEngine.mpv)));
    });

    test('Windows 默认引擎为 media_kit', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mediaKit);
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.mediaKit),
        isTrue,
      );
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isFalse);
    });

    test('旧存档 mpv 在 Windows 自动回退到 media_kit', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(
        PlayerEngineFactory.resolveSelectedEngine('mpv'),
        PlayerEngine.mediaKit,
      );
      // 显式选择 media_kit 仍生效。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mediaKit,
      );
      // 备选 MDK 仍可显式选择。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.mdk,
      );
    });

    test('Windows 不再构建 MPV 适配器（isSupported 门禁）', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      // 设置页 tab 由 supportedEngines 生成，因此 MPV 不会出现。
      expect(
        PlayerEngineFactory.supportedEngines().map((e) => e.id).toList(),
        <String>['mdk', 'media_kit', 'erika'],
      );
    });
  });

  group('641 其他平台不受影响', () {
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

      expect(PlayerEngineFactory.supportedEngines(), <PlayerEngine>[
        PlayerEngine.mpv,
      ]);
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    });

    test('iOS 仍仅 Erika', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(PlayerEngineFactory.supportedEngines(), <PlayerEngine>[
        PlayerEngine.erika,
      ]);
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.erika);
    });
  });

  group('641 源码守卫', () {
    String read(String p) => File(p).readAsStringSync();

    test('player_engine.dart 的 Windows 分支不再返回 mpv', () {
      final src = read('lib/services/player/player_engine.dart');
      final winStart = src.indexOf('case TargetPlatform.windows:');
      expect(winStart, greaterThan(-1));
      final winEnd = src.indexOf('default:', winStart);
      final winBlock = src.substring(winStart, winEnd);
      expect(winBlock, contains('PlayerEngine.mediaKit'));
      expect(winBlock, isNot(contains('PlayerEngine.mpv')));
    });
  });
}
