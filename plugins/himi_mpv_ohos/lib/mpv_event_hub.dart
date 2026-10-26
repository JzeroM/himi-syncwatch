import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'himi_mpv_ohos.dart';

/// 插件入口（供 `package:himi_mpv_ohos/himi_mpv_ohos.dart` 直接使用）。
///
/// 仅 HarmonyOS 平台注册；其他平台不应 import 本库。
class HimiMpvOhos {
  HimiMpvOhos._();

  static const MethodChannel _channel = MethodChannel('himi_mpv');

  /// 探测原生插件是否已附着。
  ///
  /// 注意：`create` 会真的分配一个 Flutter 纹理并在 finally 里 dispose，
  /// 有短暂副作用，仅供诊断/自检使用，不要在播放路径上调用。
  static Future<bool> isAvailable() async {
    try {
      final id = await _channel.invokeMethod<int>('create', {
        'width': 2,
        'height': 2,
      });
      return id != null;
    } catch (_) {
      return false;
    } finally {
      try {
        await _channel.invokeMethod<void>('dispose');
      } catch (_) {}
    }
  }
}

/// mpv 属性事件（原生 EventChannel 负载的强类型视图）。
@immutable
class MpvPropertyEvent {
  const MpvPropertyEvent(this.name, this.value);

  final String name;
  final Object? value;

  static MpvPropertyEvent? tryParse(Map<Object?, Object?> raw) {
    if (raw['type'] != 'property') return null;
    final name = raw['name'];
    if (name is! String) return null;
    return MpvPropertyEvent(name, raw['value']);
  }
}

/// mpv 事件（MPV_EVENT_*）。
@immutable
class MpvEvent {
  const MpvEvent(this.id, this.name);

  final int id;
  final String name;

  static MpvEvent? tryParse(Map<Object?, Object?> raw) {
    if (raw['type'] != 'event') return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! int || name is! String) return null;
    return MpvEvent(id, name);
  }
}

/// 便捷事件分发：把原生流拆成属性事件与 mpv 事件两个广播流。
class MpvEventHub {
  MpvEventHub._();

  static MpvEventHub? _instance;
  static MpvEventHub get instance => _instance ??= MpvEventHub._();

  Stream<MpvPropertyEvent>? _properties;
  Stream<MpvEvent>? _mpvEvents;

  Stream<MpvPropertyEvent> get properties =>
      _properties ??= HimiMpvPlayer.events
          .map(MpvPropertyEvent.tryParse)
          .where((e) => e != null)
          .cast<MpvPropertyEvent>()
          .asBroadcastStream();

  Stream<MpvEvent> get mpvEvents =>
      _mpvEvents ??= HimiMpvPlayer.events
          .map(MpvEvent.tryParse)
          .where((e) => e != null)
          .cast<MpvEvent>()
          .asBroadcastStream();

  /// 订阅某个 mpv 属性（已 observe 的属性由原生主动推送）。
  Stream<Object?> watch(String name) => properties
      .where((e) => e.name == name)
      .map((e) => e.value);

  /// 释放单例缓存（测试/热重启用）。
  static void reset() {
    _instance = null;
  }
}
