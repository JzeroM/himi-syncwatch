import 'dart:async';

import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_ohos_rtm/himi_ohos_rtm.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';

/// 鸿蒙后端：桥接 `himi_ohos_rtm` 插件（声网 RTM ArkTS SDK 2.3.0）。
///
/// 与 [WindowsRtmBackend] 结构一致——presence 的 type 以枚举传回，
/// 消息/连接事件走同一套 `{event: ...}` 结构。
class OhosRtmBackend implements RtmBackend {
  bool _ready = false;
  // 查询失败时保留上次成功值，避免一次失败把正确人数清成 0
  int _lastOnlineCount = 0;
  List<String> _lastOnlineIds = const [];

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
    _eventSubscription = HimiOhosRtmClient.events.listen(
      (event) {
        switch (event['event']) {
          case 'message':
            _messageController.add({
              'publisher': '${event['publisher'] ?? ''}',
              'message': '${event['message'] ?? ''}',
            });
          case 'presence':
            // ArkTS 侧已把 SDK 枚举映射成字符串（join/leave/timeout/other）。
            final type = _presenceTypeFromString('${event['type'] ?? ''}');
            if (type != null) {
              _presenceController.add({
                'type': type,
                'publisher': '${event['publisher'] ?? ''}',
              });
            }
          case 'connection':
            LogService().log('RTM', '连接状态: ${event['state']}');
        }
      },
      onError: (Object error) {
        LogService().log('RTM', '鸿蒙事件流错误: $error');
      },
    );
  }

  /// ArkTS 字符串 → Dart 枚举（与 SDK `RtmPresenceEventType` 对齐）。
  static RtmPresenceEventType? _presenceTypeFromString(String raw) =>
      switch (raw) {
        'join' => RtmPresenceEventType.remoteJoinChannel,
        'leave' => RtmPresenceEventType.remoteLeaveChannel,
        'timeout' => RtmPresenceEventType.remoteTimeout,
        _ => null,
      };

  @override
  Future<void> initialize({
    required String appId,
    required String userId,
  }) async {
    _ensureListening();
    final ok = await HimiOhosRtmClient.initialize(appId: appId, userId: userId);
    _ready = ok;
    if (ok) {
      LogService().log('RTM', '鸿蒙初始化成功, userId: $userId');
    } else {
      LogService().log('RTM', '鸿蒙初始化失败');
    }
  }

  @override
  Future<bool> login(String appId, {String? token}) async {
    if (!_ready) return false;
    final result = await HimiOhosRtmClient.login(token: token ?? '');
    final ok = result['ok'] == true;
    LogService().log('RTM', ok ? '登录成功' : '登录失败: ${result['reason']}');
    return ok;
  }

  @override
  Future<void> logout() async {
    if (!_ready) return;
    await HimiOhosRtmClient.logout();
    LogService().log('RTM', '登出完成');
  }

  @override
  Future<bool> subscribe(String channel) async {
    if (!_ready) return false;
    var result = await HimiOhosRtmClient.subscribe(channel);
    if (result['ok'] != true) {
      // 竞态防御：login 与 connection connected 几乎同时到达，
      // 首次订阅可能早于服务就绪，500ms 后重试一次（同 Windows）。
      LogService().log('RTM', '订阅失败: ${result['reason']}，500ms 后重试');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      result = await HimiOhosRtmClient.subscribe(channel);
    }
    final ok = result['ok'] == true;
    if (ok) {
      LogService().log('RTM', '订阅频道: $channel');
    } else {
      LogService().log('RTM', '订阅失败(重试后): ${result['reason']}');
    }
    return ok;
  }

  @override
  Future<void> unsubscribe(String channel) async {
    if (!_ready) return;
    await HimiOhosRtmClient.unsubscribe(channel);
    LogService().log('RTM', '取消订阅: $channel');
  }

  @override
  Future<bool> publish(String channel, String message) async {
    if (!_ready) return false;
    return HimiOhosRtmClient.publish(channel, message);
  }

  @override
  Future<int> getOnlineCount(String channel) async {
    if (!_ready) return _lastOnlineCount;
    final result = await HimiOhosRtmClient.getOnlineUsers(channel);
    if (result['ok'] != true) {
      LogService().log('RTM', '查询在线人数失败: ${result['reason']}');
      return _lastOnlineCount;
    }
    final value = result['value'];
    final count = value is Map && value['count'] is int
        ? value['count'] as int
        : 0;
    _lastOnlineCount = count;
    return count;
  }

  @override
  Future<List<String>> getOnlineIds(String channel) async {
    if (!_ready) return _lastOnlineIds;
    final result = await HimiOhosRtmClient.getOnlineUsers(channel);
    if (result['ok'] != true) {
      LogService().log('RTM', '查询在线用户失败: ${result['reason']}');
      return _lastOnlineIds;
    }
    final value = result['value'];
    final raw = value is Map ? value['userIds'] : null;
    final ids = raw is List ? raw.map((e) => '$e').toList() : const <String>[];
    _lastOnlineIds = ids;
    return ids;
  }

  @override
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    if (!_ready) return 'storage_null';
    return HimiOhosRtmClient.setChannelMetadata(
      channel: channelName,
      metadata: metadata,
    );
  }

  @override
  Future<(Map<String, String>, String)> getChannelMetadata(
    String channelName,
  ) async {
    if (!_ready) return (const <String, String>{}, 'storage_null');
    return HimiOhosRtmClient.getChannelMetadata(channelName);
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await HimiOhosRtmClient.release();
    await _messageController.close();
    await _presenceController.close();
  }
}
