import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// fvp 版本守卫回归测试（v1.2.5）。
///
/// fvp 0.39.1 修复两条与本项目相关的崩溃/异常（原生 mdk-sdk 仍为 v0.39.0，
/// 无 0.39.1）：
///  1. `ios: release texture players on scene disconnect, fix crash` ——
///     `FvpPlugin.mm` 注册 scene delegate，`sceneDidDisconnect:` 释放纹理播放器
///     （himi 经 `Player.updateTexture` 走 fvp 纹理通道，scene 断开时旧版会崩）。
///  2. `fix: Unhandled Exception: Bad state: Cannot add event after closing` ——
///     `video_player_mdk.dart` 在 `streamCtl.isClosed` 时提前 return，避免
///     player 销毁后原生回调仍向已关闭的 StreamController 追加事件。
///
/// 本题防止依赖被无意降级回 0.39.0（丢修复）：约束下界与 lock 解析版本
/// 都必须 >= 0.39.1。
void main() {
  (int, int, int) parseVersion(String v) {
    final parts = v.trim().split('+').first.split('.');
    int at(int i) =>
        i < parts.length ? (int.tryParse(parts[i].replaceAll(RegExp(r'\D'), '')) ?? 0) : 0;
    return (at(0), at(1), at(2));
  }

  bool gte((int, int, int) a, (int, int, int) b) {
    if (a.$1 != b.$1) return a.$1 > b.$1;
    if (a.$2 != b.$2) return a.$2 > b.$2;
    return a.$3 >= b.$3;
  }

  const required = (0, 39, 1);

  test('pubspec.yaml 的 fvp 约束下界 >= 0.39.1', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^\s*fvp:\s*\^?([0-9]+\.[0-9]+\.[0-9]+)',
            multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 必须声明 fvp 依赖');
    final lower = parseVersion(m!.group(1)!);
    expect(
      gte(lower, required),
      isTrue,
      reason: 'fvp 约束下界 ${m.group(1)} < 0.39.1：会丢掉 iOS scene 崩溃 / '
          'add-after-close 两条修复',
    );
  });

  test('pubspec.lock 解析到的 fvp 版本 >= 0.39.1', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final block = RegExp(r'^\s{2}fvp:.*?(?=^\s{2}\w)',
            multiLine: true, dotAll: true)
        .firstMatch(lock);
    expect(block, isNotNull, reason: 'pubspec.lock 必须包含 fvp 条目');
    final m = RegExp(r'version:\s*"([^"]+)"').firstMatch(block!.group(0)!);
    expect(m, isNotNull, reason: 'fvp 锁定条目必须含 version 字段');
    final resolved = parseVersion(m!.group(1)!);
    expect(
      gte(resolved, required),
      isTrue,
      reason: 'fvp 实际解析到 ${m.group(1)} < 0.39.1：需要 `flutter pub upgrade fvp`',
    );
  });
}
