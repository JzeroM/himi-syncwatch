import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android 原生播放器 UI 通道（计划书 §6.1）：`himi_native_player`。
///
/// Compose Dialog 宿主（`com.himi.syncwatch.nativeplayer`）：open 显示
/// 全屏 Dialog 并注入 SurfaceView，close 关闭并释放；pushNativeState
/// 接收 Dart 权威状态 JSON；commands 回传 UI 侧手势/按钮命令。
/// 非 Android 平台所有调用均为 no-op（门控已在上游排除）。
class AndroidNativePlayer {
  AndroidNativePlayer._();

  static const MethodChannel channel = MethodChannel('himi_native_player');
  static const EventChannel _commands =
      EventChannel('himi_native_player/commands');

  static Stream<Map<Object?, Object?>>? _commandStream;

  static bool get supported => Platform.isAndroid;

  /// 原生 UI 命令流（原生 → Dart；单例广播，同鸿蒙 himi_mpv/native_ui）。
  static Stream<Map<Object?, Object?>> get commandStream {
    final existing = _commandStream;
    if (existing != null) return existing;
    final stream = _commands
        .receiveBroadcastStream()
        .map((e) => e is Map<Object?, Object?> ? e : <Object?, Object?>{})
        .asBroadcastStream();
    _commandStream = stream;
    return stream;
  }

  /// 打开全屏原生播放器 Dialog（幂等）。
  static Future<void> open() async {
    if (!supported) return;
    await channel.invokeMethod<void>('open');
  }

  /// 关闭原生播放器 Dialog（幂等）。
  static Future<void> close() async {
    if (!supported) return;
    await channel.invokeMethod<void>('close');
  }

  /// Dart → 原生：推送权威状态 JSON 快照。
  static Future<void> pushNativeState(String stateJson) async {
    if (!supported) return;
    await channel.invokeMethod<void>('pushNativeState', {'state': stateJson});
  }
}
