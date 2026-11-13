import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/himi_platform.dart';

/// 697：鸿蒙平台判定。
///
/// ## 为什么需要单独测
///
/// 项目同时用两套 Flutter SDK：
/// - 鸿蒙：`flutter_ohos`，`TargetPlatform` 里有 `ohos`；
/// - 其它：stock Flutter，**枚举里没有 `ohos`**。
///
/// 所以代码里**不能写 `TargetPlatform.ohos`**（stock SDK 会编译失败），
/// 只能按 `name == 'ohos'` 判断。这类「按字符串判定」最容易在重构中退化，
/// 因此用 `debugIsOhosOverride` 钉住行为，并额外扫描源码防回归。
///
/// ## 687 遗留 bug（697 修复）
///
/// 687 的滚动物理 / 页面转场 / 玻璃滑杆可见性都只列了 android / iOS，
/// 鸿蒙因此落到桌面分支：
/// - 滑动无回弹（硬撞墙）
/// - 页面转场走框架兜底 Zoom（不是横滑）
/// - 折射范围滑杆被隐藏（但鸿蒙同走 standard 路径）
void main() {
  tearDown(() {
    HimiPlatform.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('HimiPlatform.isOhos', () {
    test('override=true 时判定为鸿蒙', () {
      HimiPlatform.debugIsOhosOverride = true;
      expect(HimiPlatform.isOhos, isTrue);
    });

    test('override=false 时判定为非鸿蒙', () {
      HimiPlatform.debugIsOhosOverride = false;
      expect(HimiPlatform.isOhos, isFalse);
    });

    test('未覆盖时按实际平台判定（测试环境不是鸿蒙）', () {
      expect(HimiPlatform.isOhos, isFalse);
    });
  });

  group('HimiPlatform.isTouchFirst', () {
    test('鸿蒙算触屏（override）', () {
      HimiPlatform.debugIsOhosOverride = true;
      expect(HimiPlatform.isTouchFirst, isTrue);
    });

    test('Android 算触屏', () {
      HimiPlatform.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(HimiPlatform.isTouchFirst, isTrue);
    });

    test('iOS 算触屏', () {
      HimiPlatform.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(HimiPlatform.isTouchFirst, isTrue);
    });

    test('桌面三端不算触屏', () {
      HimiPlatform.debugIsOhosOverride = false;
      for (final p in const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(HimiPlatform.isTouchFirst, isFalse, reason: '$p 是桌面');
      }
    });

    test('鸿蒙 override 优先于实际平台（stock SDK 无法表达 ohos）', () {
      HimiPlatform.debugIsOhosOverride = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(HimiPlatform.isTouchFirst, isTrue,
          reason: '鸿蒙覆盖应压过 windows 枚举');
    });
  });

  group('源码不直接引用 TargetPlatform.ohos', () {
    test('lib/ 下无该枚举字面量（stock SDK 会编译失败）', () {
      // 兜底扫描：万一有人图省事写死枚举值，这里立刻报错。
      //
      // 只扫**代码行**：注释里出现 `TargetPlatform.ohos` 是合法的
      // （用于解释「为什么不能这么写」）。
      final offenders = <String>[];
      final root = Directory('lib');
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = entity
            .readAsStringSync()
            .split('\n')
            .where((l) {
              final t = l.trimLeft();
              return !t.startsWith('//') && !t.startsWith('*');
            })
            .join('\n');
        if (code.contains('TargetPlatform.ohos')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '请改用 HimiPlatform.isOhos（按 name 判定）');
    });
  });
}
