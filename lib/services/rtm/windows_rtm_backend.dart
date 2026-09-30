import 'dart:async';

import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';
import 'package:himi_windows_rtm/himi_windows_rtm.dart';

/// Windows 后端：桥接 himi_windows_rtm 插件（Agora RTM C++ SDK 2.2.5）。
///
/// presence 的 type 在 C++ 侧为 int（RTM_PRESENCE_EVENT_TYPE），
/// 与 RtmPresenceEventType 枚举索引一一对应（@JsonValue 同序）。
class WindowsRtmBackend implements RtmBackend {
  bool _ready = false;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController.broadcast();
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _ready;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  void _ensureListening() {
    if (_eventSubscription != null) return;
    _eventSubscription = WindowsRtmClient.events.listen(
      (event) {
        switch (event['event']) {
          case 'message':
            _messageController.add({
              'publisher': '${event['publisher'] ?? ''}',
              'message': '${event['message'] ?? ''}',
            });
          case 'presence':
            final typeIndex = event['type'];
            if (typeIndex is int &&
                typeIndex >= 0 &&
                typeIndex < RtmPresenceEventType.values.length) {
              _presenceController.add({
                'type': RtmPresenceEventType.values[typeIndex],
                'publisher': '${event['publisher'] ?? ''}',
              });
            }
          case 'connection':
            LogService().log('RTM', '连接状态: ${event['state']}');
          case 'result':
            // 结果事件由 WindowsRtmClient.invokeForResult 按 requestId 消费
            break;
        }
      },
      onError: (Object error) {
        LogService().log('RTM', 'Windows 事件流错误: $error');
      },
    );
  }

  @override
  Future<void> initialize({required String appId, required String userId}) async {
    _ensureListening();
    final ok = await WindowsRtmClient.initialize(appId: appId, userId: userId);
    _ready = ok;
    if (ok) {
      LogService().log('RTM', 'Windows 初始化成功, userId: $userId');
    } else {
      LogService().log('RTM', 'Windows 初始化失败');
    }
  }

  @override
  Future<bool> login(String appId, {String? token}) async {
    if (!_ready) return false;
    final ok = await WindowsRtmClient.login(token: token);
    LogService().log('RTM', ok ? '登录成功' : '登录失败');
    return ok;
  }

  @override
  Future<void> logout() async {
    if (!_ready) return;
    await WindowsRtmClient.logout();
    LogService().log('RTM', '登出完成');
  }

  @override
  Future<bool> subscribe(String channel) async {
    if (!_ready) return false;
    final ok = await WindowsRtmClient.subscribe(channel);
    if (ok) {
      LogService().log('RTM', '订阅频道: $channel');
    } else {
      LogService().log('RTM', '订阅失败');
    }
    return ok;
  }

  @override
  Future<void> unsubscribe(String channel) async {
    if (!_ready) return;
    await WindowsRtmClient.unsubscribe(channel);
    LogService().log('RTM', '取消订阅: $channel');
  }

  @override
  Future<bool> publish(String channel, String message) async {
    if (!_ready) return false;
    return WindowsRtmClient.publish(channel, message);
  }

  @override
  Future<int> getOnlineCount(String channel) async {
    if (!_ready) return 0;
    final result = await WindowsRtmClient.getOnlineUsers(channel);
    if (result == null) return 0;
    return result['count'] is int ? result['count'] as int : 0;
  }

  @override
  Future<List<String>> getOnlineIds(String channel) async {
    if (!_ready) return [];
    final result = await WindowsRtmClient.getOnlineUsers(channel);
    if (result == null) return [];
    return (result['userIds'] as List?)?.cast<String>() ?? const <String>[];
  }

  @override
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    if (!_ready) return 'storage_null';
    return WindowsRtmClient.setChannelMetadata(
      channel: channelName,
      metadata: metadata,
    );
  }

  @override
  Future<(Map<String, String>, String)> getChannelMetadata(
      String channelName) async {
    if (!_ready) return (const <String, String>{}, 'storage_null');
    return WindowsRtmClient.getChannelMetadata(channelName);
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await WindowsRtmClient.release();
    await _messageController.close();
    await _presenceController.close();
  }
}
