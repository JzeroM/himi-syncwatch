import 'dart:async';

import 'package:flutter/services.dart';

/// Windows 端 RTM 客户端：MethodChannel/EventChannel 桥接到
/// Agora RTM C++ SDK（agora_rtm_sdk.dll）。
///
/// 能力面与 [RtmService] 所需一一对应：登录/登出、订阅/退订、
/// 发布消息、消息与 presence 事件、在线用户查询、频道元数据。
class WindowsRtmClient {
  static const MethodChannel methodChannel = MethodChannel('himi_windows_rtm');
  static const EventChannel eventChannel = EventChannel('himi_windows_rtm/events');

  static Stream<Map<String, dynamic>>? _events;

  /// SDK 事件流：`{event: message|presence|connection|login|subscribe|publish|getOnlineUsers|metadata, ...}`
  static Stream<Map<String, dynamic>> get events {
    return _events ??= eventChannel.receiveBroadcastStream().map((e) {
      return Map<String, dynamic>.from(e as Map);
    });
  }

  /// 创建并初始化 RTM 客户端；返回是否成功。
  static Future<bool> initialize({
    required String appId,
    required String userId,
  }) async {
    final ok = await methodChannel.invokeMethod<bool>('initialize', {
      'appId': appId,
      'userId': userId,
    });
    return ok ?? false;
  }

  static Future<bool> login({String? token}) async {
    final ok = await methodChannel.invokeMethod<bool>('login', {'token': token});
    return ok ?? false;
  }

  static Future<bool> logout() async {
    return await methodChannel.invokeMethod<bool>('logout') ?? false;
  }

  static Future<bool> subscribe(String channel) async {
    final ok =
        await methodChannel.invokeMethod<bool>('subscribe', {'channel': channel});
    return ok ?? false;
  }

  static Future<bool> unsubscribe(String channel) async {
    final ok = await methodChannel
        .invokeMethod<bool>('unsubscribe', {'channel': channel});
    return ok ?? false;
  }

  /// 发布 UTF-8 文本消息到频道；返回是否成功。
  static Future<bool> publish(String channel, String message) async {
    final ok = await methodChannel.invokeMethod<bool>('publish', {
      'channel': channel,
      'message': message,
    });
    return ok ?? false;
  }

  /// 查询在线用户：返回 `{count: int, userIds: List<String>}`；失败返回 null。
  static Future<Map<String, dynamic>?> getOnlineUsers(String channel) async {
    final result = await methodChannel
        .invokeMethod<Map>('getOnlineUsers', {'channel': channel});
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  /// 写入频道元数据；返回诊断字符串（与 RtmService 约定一致）。
  static Future<String> setChannelMetadata({
    required String channel,
    required Map<String, String> metadata,
  }) async {
    final diag = await methodChannel.invokeMethod<String>('setChannelMetadata', {
      'channel': channel,
      'metadata': metadata,
    });
    return diag ?? 'exception:channel_error';
  }

  /// 读取频道元数据；返回 `{data: Map, diagnostic: String}`。
  static Future<(Map<String, String>, String)> getChannelMetadata(
      String channel) async {
    final result = await methodChannel
        .invokeMethod<Map>('getChannelMetadata', {'channel': channel});
    if (result == null) {
      return (const <String, String>{}, 'exception:channel_error');
    }
    final map = Map<String, dynamic>.from(result);
    final Map<String, String> data =
        Map<String, String>.from(map['data'] as Map? ?? const {});
    final diag = map['diagnostic'] as String? ?? 'ok';
    return (data, diag);
  }

  static Future<void> release() async {
    await methodChannel.invokeMethod('release');
  }
}
