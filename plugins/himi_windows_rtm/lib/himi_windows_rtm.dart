import 'dart:async';

import 'package:flutter/services.dart';

/// Windows 端 RTM 客户端：MethodChannel/EventChannel 桥接到
/// Agora RTM C++ SDK（agora_rtm_sdk.dll）。
///
/// 协议：需要结果的方法返回 `{rid}`（SDK requestId），结果经事件流
/// 以 `{event: 'result', requestId, method, ok, ...}` 推回；
/// Dart 侧按 rid 关联等待（带超时兜底）。
class WindowsRtmClient {
  WindowsRtmClient._();

  static const MethodChannel methodChannel = MethodChannel('himi_windows_rtm');
  static const EventChannel eventChannel =
      EventChannel('himi_windows_rtm/events');

  static final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  static final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  static bool _listening = false;

  /// SDK 事件流（广播）。
  static Stream<Map<String, dynamic>> get events => _controller.stream;

  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    eventChannel.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event as Map);
      _controller.add(map);
      final requestId = map['requestId'];
      if (map['event'] == 'result' && requestId is int) {
        _pending.remove(requestId)?.complete(map);
      }
    }, onError: (Object error) {
      _controller.addError(error);
      for (final completer in _pending.values) {
        completer.complete({'event': 'result', 'ok': false, 'reason': '$error'});
      }
      _pending.clear();
    });
  }

  static const Duration _resultTimeout = Duration(seconds: 12);

  /// 发起需要结果的方法并按 rid 等待结果事件。
  /// 返回结果 map；超时/通道失败返回 `{ok: false, reason: ...}`。
  static Future<Map<String, dynamic>> invokeForResult(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    _ensureListening();
    final Map<dynamic, dynamic>? response;
    try {
      response = await methodChannel.invokeMethod<Map>(method, arguments);
    } on PlatformException catch (e) {
      return {'event': 'result', 'ok': false, 'reason': e.message ?? e.code};
    }
    final rid = response?['rid'];
    if (rid is! int || rid == 0) {
      return {
        'event': 'result',
        'ok': false,
        'reason': '客户端未就绪',
      };
    }
    final completer = Completer<Map<String, dynamic>>();
    _pending[rid] = completer;
    try {
      return await completer.future.timeout(_resultTimeout);
    } on TimeoutException {
      _pending.remove(rid);
      return {
        'event': 'result',
        'requestId': rid,
        'method': method,
        'ok': false,
        'reason': '等待结果超时',
      };
    }
  }

  /// 创建并初始化 RTM 客户端（同步创建，成功返回 true）。
  static Future<bool> initialize({
    required String appId,
    required String userId,
  }) async {
    _ensureListening();
    try {
      return await methodChannel.invokeMethod<bool>('initialize', {
        'appId': appId,
        'userId': userId,
      }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> login({String? token}) async {
    final result = await invokeForResult('login', {'token': token ?? ''});
    return result['ok'] == true;
  }

  static Future<bool> logout() async {
    _ensureListening();
    try {
      return await methodChannel.invokeMethod<bool>('logout') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> subscribe(String channel) async {
    final result =
        await invokeForResult('subscribe', {'channel': channel});
    return result['ok'] == true;
  }

  static Future<bool> unsubscribe(String channel) async {
    _ensureListening();
    try {
      return await methodChannel
              .invokeMethod<bool>('unsubscribe', {'channel': channel}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 发布消息（fire-and-forget：高频心跳场景不等待回执）。
  static Future<bool> publish(String channel, String message) async {
    _ensureListening();
    try {
      await methodChannel.invokeMethod('publish', {
        'channel': channel,
        'message': message,
      });
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// 查询在线用户：`{count, userIds}`；失败返回 null。
  static Future<Map<String, dynamic>?> getOnlineUsers(String channel) async {
    final result =
        await invokeForResult('getOnlineUsers', {'channel': channel});
    if (result['ok'] != true) return null;
    return {
      'count': result['count'] is int ? result['count'] : 0,
      'userIds': (result['userIds'] as List?)?.cast<String>() ?? const <String>[],
    };
  }

  /// 写入频道元数据；返回诊断字符串。
  static Future<String> setChannelMetadata({
    required String channel,
    required Map<String, String> metadata,
  }) async {
    final result = await invokeForResult('setChannelMetadata', {
      'channel': channel,
      'metadata': metadata,
    });
    if (result['ok'] == true) {
      var totalLen = 0;
      for (final entry in metadata.entries) {
        totalLen += entry.key.length + entry.value.length;
      }
      return 'ok,${metadata.length}keys,${totalLen}chars';
    }
    final reason = '${result['reason'] ?? 'unknown'}';
    if (reason.contains('超时')) return 'exception:$reason';
    return 'error:$reason';
  }

  /// 读取频道元数据；返回 `(data, diagnostic)`。
  static Future<(Map<String, String>, String)> getChannelMetadata(
      String channel) async {
    final result = await invokeForResult('getChannelMetadata', {'channel': channel});
    if (result['ok'] != true) {
      return (const <String, String>{}, 'error:${result['reason'] ?? 'unknown'}');
    }
    final raw = result['metadata'];
    final data = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) data[key] = value;
      });
    }
    return (data, 'ok,${data.length}items,keys=${data.keys.toList()}');
  }

  static Future<void> release() async {
    _ensureListening();
    try {
      await methodChannel.invokeMethod('release');
    } on PlatformException {
      // 忽略：释放失败不阻塞
    }
  }
}
