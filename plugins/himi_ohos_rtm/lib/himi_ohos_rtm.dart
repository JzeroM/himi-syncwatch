import 'dart:async';

import 'package:flutter/services.dart';

/// 鸿蒙端 RTM 客户端：MethodChannel/EventChannel 桥接到声网 RTM 原生库
/// （`libagora-rtm-sdk.so`，NAPI 直连，绕开 bytecode HAR 的
/// `useNormalizedOHMUrl` 依赖——详见 ArkTS 侧 `RtmManager.ets` 注释）。
///
/// 与 Windows 插件的差异：鸿蒙原生库全部 API 返回 **Promise**，ArkTS 侧
/// 可直接 `await` 后回传结果——不需要 requestId 关联机制。
class HimiOhosRtmClient {
  HimiOhosRtmClient._();

  static const MethodChannel methodChannel = MethodChannel('himi_ohos_rtm');
  static const EventChannel eventChannel =
      EventChannel('himi_ohos_rtm/events');

  static final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  static StreamSubscription<dynamic>? _eventSubscription;
  static bool _listening = false;

  /// SDK 事件流（广播）。
  static Stream<Map<String, dynamic>> get events => _controller.stream;

  static void _ensureListening() {
    // 634：除标志位外还校验订阅对象是否仍有效——防止「标志为 true 但订阅
    // 已被外部取消」的僵尸状态（dispose 取消订阅却没复位标志）。
    if (_listening && _eventSubscription != null) return;
    _listening = true;
    _eventSubscription =
        eventChannel.receiveBroadcastStream().listen((event) {
      _controller.add(Map<String, dynamic>.from(event as Map));
    }, onError: (Object error) {
      _controller.addError(error);
    });
  }

  /// 测试专用：断开事件订阅，允许下一次测试重建 listen。
  static Future<void> debugReset() => _resetListening();

  /// 通用调用：把 MethodChannel 的异常转成 `{ok:false, reason}`，调用方无需
  /// 逐个 try/catch（与 Windows 插件的 result map 语义对齐）。
  static Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    _ensureListening();
    try {
      final result = await methodChannel.invokeMethod<Object?>(method, args);
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return <String, dynamic>{'ok': true, 'value': result};
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'reason': e.message ?? e.code,
      };
    } on MissingPluginException catch (e) {
      return <String, dynamic>{'ok': false, 'reason': '$e'};
    }
  }

  static Future<bool> initialize({
    required String appId,
    required String userId,
  }) async {
    final r = await _invoke('initialize', {'appId': appId, 'userId': userId});
    return r['ok'] == true;
  }

  static Future<Map<String, dynamic>> login({String token = ''}) =>
      _invoke('login', {'token': token});

  static Future<void> logout() => _invoke('logout');

  static Future<Map<String, dynamic>> subscribe(String channel) =>
      _invoke('subscribe', {'channel': channel});

  static Future<void> unsubscribe(String channel) =>
      _invoke('unsubscribe', {'channel': channel});

  static Future<bool> publish(String channel, String message) async {
    final r = await _invoke('publish', {'channel': channel, 'message': message});
    return r['ok'] == true;
  }

  /// 在线人数 + 用户 ID 一次查回（`presence.whoNow`）。
  static Future<Map<String, dynamic>> getOnlineUsers(String channel) =>
      _invoke('getOnlineUsers', {'channel': channel});

  static Future<String> setChannelMetadata({
    required String channel,
    required Map<String, String> metadata,
  }) async {
    final r = await _invoke('setChannelMetadata', {
      'channel': channel,
      'metadata': metadata,
    });
    return r['ok'] == true ? '${r['value'] ?? ''}' : 'storage_null';
  }

  static Future<(Map<String, String>, String)> getChannelMetadata(
    String channel,
  ) async {
    final r = await _invoke('getChannelMetadata', {'channel': channel});
    if (r['ok'] != true) {
      return (const <String, String>{}, 'storage_null');
    }
    final raw = r['metadata'];
    final map = raw is Map
        ? raw.map((k, v) => MapEntry('$k', '$v'))
        : <String, String>{};
    return (map, '${r['updatedAt'] ?? ''}');
  }

  static Future<void> release() async {
    await _invoke('release');
    // 634：**必须**重置事件监听状态。
    //
    // 真机回归：第一次进房正常；重进房 / 房主重开房后再加入 → 约 20 秒后
    // 弹「房间已解散」并退回首页，但**在线人数与播报都正常**。
    //
    // 根因：`_listening` 是**静态**标志。`RtmService.dispose()` →
    // `backend.dispose()` 会取消 EventChannel 订阅，却没复位该标志 →
    // 第二次 `_ensureListening()` 看到 `_listening == true` 直接 return →
    // EventChannel 永不重新订阅 → 消息流 / presence 流永久失效。
    // 在线人数走 `whoNow` 直调 MethodChannel、播报是本地添加，故二者仍正常，
    // 只有依赖 EventChannel 的资源列表与房主离线检测失效。
    await _resetListening();
  }

  /// 634：断开并复位事件监听，使下一次 [_ensureListening] 能重新订阅。
  static Future<void> _resetListening() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _listening = false;
  }
}
