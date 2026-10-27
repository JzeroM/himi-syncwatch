import 'package:flutter/services.dart';

import 'himi_mpv_ohos.dart';

export 'package:himi_mpv_core/himi_mpv_core.dart'
    show MpvEvent, MpvPropertyEvent;

/// 插件入口（供 `package:himi_mpv_ohos/himi_mpv_ohos.dart` 直接使用）。
///
/// 仅 HarmonyOS 平台注册；其他平台不应 import 本库。
class HimiMpvOhos {
  HimiMpvOhos._();

  static const MethodChannel _channel = MethodChannel('himi_mpv');

  /// 探测原生插件是否已附着。
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

/// 便捷事件分发：把原生流拆成属性事件与 mpv 事件两个广播流。
class MpvEventHub {
  MpvEventHub._();

  static MpvEventHub? _instance;
  static MpvEventHub get instance => _instance ??= MpvEventHub._();

  Stream<MpvPropertyEvent>? _properties;
  Stream<MpvEvent>? _mpvEvents;

  Stream<MpvPropertyEvent> get properties =>
      _properties ??= HimiMpvPlayer.eventStream
          .map(MpvPropertyEvent.tryParse)
          .where((e) => e != null)
          .cast<MpvPropertyEvent>()
          .asBroadcastStream();

  Stream<MpvEvent> get mpvEvents => _mpvEvents ??= HimiMpvPlayer.eventStream
      .map(MpvEvent.tryParse)
      .where((e) => e != null)
      .cast<MpvEvent>()
      .asBroadcastStream();

  Stream<Object?> watch(String name) =>
      properties.where((e) => e.name == name).map((e) => e.value);

  static void reset() {
    _instance = null;
  }
}
