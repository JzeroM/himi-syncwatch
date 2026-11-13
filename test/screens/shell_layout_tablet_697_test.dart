import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/himi_platform.dart';

/// 697：壳层布局判定必须区分「桌面平台」与「移动平板」。
///
/// ## 用户反馈
///
/// 「鸿蒙平板安装后为啥是 win 版布局」——即底部胶囊导航变成了左缘
/// 侧边栏（百叶窗抽屉）。
///
/// ## 根因
///
/// `main_shell.dart` 旧判定只看逻辑宽度：
///
/// ```dart
/// final isDesktop = MediaQuery.sizeOf(context).width >= kShellDesktopBreakpoint;
/// ```
///
/// `kShellDesktopBreakpoint = 1000`。鸿蒙平板横屏逻辑宽度普遍 1200+，
/// 直接落进桌面侧边栏布局——但平板是触屏设备，没有鼠标/键盘，
/// 侧边栏交互（悬停吊绳、抽屉展开）完全不适用。
///
/// ## 修复
///
/// 判定改为「**桌面平台** && 宽窗口」：Android / iOS / 鸿蒙（含平板）
/// 一律手机布局（底部胶囊），与手机一致。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String shell;

  setUpAll(() => shell = read('lib/screens/shell/main_shell.dart'));

  tearDown(() {
    HimiPlatform.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('1. 桌面布局只给真桌面平台', () {
    test('1.1 提供 _isDesktopPlatform 判定', () {
      expect(codeOnly(shell), contains('bool get _isDesktopPlatform'));
    });

    test('1.2 桌面三端算桌面', () {
      final code = codeOnly(shell);
      for (final p in const ['windows', 'macOS', 'linux']) {
        expect(code, contains('TargetPlatform.$p'),
            reason: '$p 应被识别为桌面平台');
      }
    });

    test('1.3 鸿蒙明确排除（含平板）', () {
      final idx = shell.indexOf('bool get _isDesktopPlatform');
      final block = shell.substring(idx, idx + 400);
      expect(block, contains('HimiPlatform.isOhos'));
      expect(block, contains('return false'));
    });

    test('1.4 isDesktop = 桌面平台 && 宽度达标', () {
      final code = codeOnly(shell);
      expect(code, contains('_isDesktopPlatform &&'));
      expect(code, contains('kShellDesktopBreakpoint'));
      // 不得再出现「只看宽度」的裸判定
      expect(code, isNot(contains('final isDesktop =\n        MediaQuery')));
    });
  });

  group('2. 滚动显隐与布局判定保持一致', () {
    test('2.1 _handleScroll 也走平台判定', () {
      final idx = shell.indexOf('bool _handleScroll');
      final block = shell.substring(idx, idx + 900);
      expect(block, contains('_isDesktopPlatform'));
      expect(block, contains('kShellDesktopBreakpoint'));
    });

    test('2.2 两处判定条件相同（避免胶囊显示但不随滚动隐藏）', () {
      final occurrences =
          '_isDesktopPlatform &&'.allMatches(codeOnly(shell)).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: 'build 与 _handleScroll 都需平台判定，否则行为错位');
    });
  });

  group('3. 平台判定工具行为', () {
    test('3.1 鸿蒙 override → 非桌面', () {
      HimiPlatform.debugIsOhosOverride = true;
      expect(HimiPlatform.isOhos, isTrue);
    });

    test('3.2 Android / iOS 不是桌面平台', () {
      HimiPlatform.debugIsOhosOverride = false;
      for (final p in const [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = p;
        final isDesktop = p == TargetPlatform.windows ||
            p == TargetPlatform.macOS ||
            p == TargetPlatform.linux;
        expect(isDesktop, isFalse, reason: '$p 不应是桌面布局');
      }
    });

    test('3.3 桌面三端是桌面平台', () {
      for (final p in const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final isDesktop = p == TargetPlatform.windows ||
            p == TargetPlatform.macOS ||
            p == TargetPlatform.linux;
        expect(isDesktop, isTrue, reason: '$p 应是桌面布局');
      }
    });
  });

  group('4. 文档注释已更新', () {
    test('4.1 类注释写明「桌面平台且宽窗口」', () {
      expect(shell, contains('**桌面平台**且宽窗口'));
      expect(shell, contains('移动平台（含平板）'));
    });
  });
}
