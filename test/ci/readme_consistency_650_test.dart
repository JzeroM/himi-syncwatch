import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 650：README 与代码实际状态保持一致。
///
/// 【为什么需要】README 长期未更新，积累了多处过时描述：
/// - Windows 默认引擎写「MDK」，实际已是 **MPV**（646.1 起）
/// - Android 默认引擎写「MDK」，实际已是 **MPV**（2026-10 起）
/// - 引擎数量写「三播放引擎」，实际有四个（MDK/media_kit/Erika/MPV）
/// - 技术栈表 Windows 写「media_kit」，实际默认 MPV
/// - 说明文字写「自编译 libmpv 内核」，638 起已改为官方 + shinchiro
/// - 项目结构缺 `player_core/` 与 `plugins/`
void main() {
  late String readme;
  late String engineSrc;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
    engineSrc = File('lib/services/player/player_engine.dart').readAsStringSync();
  });

  group('① 引擎数量与列表', () {
    test('README 写「四播放引擎」', () {
      expect(readme, contains('四播放引擎'));
      expect(readme, isNot(contains('三播放引擎')));
    });

    test('特性表列出 MPV', () {
      expect(readme, contains('**MPV**'));
      expect(readme, contains('原生 Surface'));
    });
  });

  group('② 平台默认引擎与代码一致', () {
    test('代码：Windows 默认 MPV', () {
      final start = engineSrc.indexOf('static PlayerEngine defaultEngine()');
      expect(start, greaterThan(-1));
      final body = engineSrc.substring(start);
      final winIdx = body.indexOf('TargetPlatform.windows');
      expect(winIdx, greaterThan(-1));
      final winBlock = body.substring(winIdx);
      expect(winBlock, contains('return PlayerEngine.mpv'));
    });

    test('README：Windows 默认 MPV', () {
      expect(readme, contains('Windows x64 | 10+ | MPV'));
    });

    test('代码：Android 默认 MPV', () {
      final start = engineSrc.indexOf('static PlayerEngine defaultEngine()');
      final body = engineSrc.substring(start);
      final andIdx = body.indexOf('TargetPlatform.android');
      expect(andIdx, greaterThan(-1));
      final andBlock = body.substring(andIdx);
      expect(andBlock, contains('return PlayerEngine.mpv'));
    });

    test('README：Android 默认 MPV', () {
      expect(readme, contains('Android | 8.0（API 26） | MPV'));
    });

    test('README：TV 模式支持 MPV', () {
      expect(readme, contains('支持 MPV / MDK / Erika'));
    });
  });

  group('③ 过时描述已清除', () {
    test('不再写「自编译 libmpv 内核」', () {
      expect(
        readme,
        isNot(contains('自编译 libmpv 内核')),
        reason: '638 起改为 media_kit 官方 + shinchiro 完整版',
      );
    });

    test('技术栈不再把 media_kit 标为 Windows 默认', () {
      expect(
        readme,
        isNot(contains('播放引擎（Windows） | media_kit')),
      );
    });

    test('技术栈包含 MPV 行', () {
      expect(readme, contains('播放引擎（Android/Windows/鸿蒙，默认）'));
    });
  });

  group('④ 项目结构完整', () {
    test('列出 player_core/', () {
      expect(readme, contains('player_core/'));
    });

    test('列出 plugins/ 及各平台插件', () {
      expect(readme, contains('plugins/'));
      for (final p in [
        'himi_mpv_core',
        'himi_mpv_android',
        'himi_mpv_ohos',
        'himi_mpv_windows',
      ]) {
        expect(readme, contains(p), reason: '缺少插件 $p');
      }
    });
  });

  group('⑤ 基本信息', () {
    test('平台覆盖 5 个平台', () {
      for (final p in ['Android', 'iOS', 'Windows', 'Android TV', 'HarmonyOS']) {
        expect(readme, contains(p), reason: '缺少平台 $p');
      }
    });

    test('下载说明列出四类产物', () {
      expect(readme, contains('.apk'));
      expect(readme, contains('-setup.exe'));
      expect(readme, contains('.zip'));
      expect(readme, contains('.ipa'));
    });
  });
}
