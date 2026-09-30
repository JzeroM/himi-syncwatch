import 'dart:async';
import 'dart:convert';

import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';

/// agora_rtm 插件后端（Android / iOS）：现网已验证的实现。
class AgoraRtmBackend implements RtmBackend {
  RtmClient? _client;
  RtmStorage? _storage;
  RtmPresence? _presence;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController.broadcast();

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _client != null;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  @override
  Future<void> initialize({required String appId, required String userId}) async {
    await _releaseClient();

    const rtmConfig = RtmConfig(
      areaCode: {RtmAreaCode.glob},
      useStringUserId: true,
      heartbeatInterval: 15,
      presenceTimeout: 300,
    );

    try {
      final (status, client) = await RTM(appId, userId, config: rtmConfig);

      if (status.error == true) {
        LogService().log('RTM', '初始化失败: ${status.reason}');
        return;
      }

      _client = client;
      _storage = client.getStorage();
      _presence = client.getPresence();
      LogService().log('RTM', '初始化成功, userId: $userId');

      _client?.addListener(
        message: (event) {
          try {
            if (event.message != null) {
              final raw = utf8.decode(event.message!);
              final publisher = event.publisher ?? '';
              _messageController.add({'publisher': publisher, 'message': raw});
            }
          } catch (e) {
            LogService().log('RTM', '消息解码失败: $e');
          }
        },
        linkState: (event) {
          LogService().log('RTM', '连接状态: ${event.currentState}');
        },
        presence: (event) {
          _presenceController.add({
            'type': event.type,
            'publisher': event.publisher,
          });
        },
      );
    } catch (e) {
      LogService().log('RTM', '初始化异常: $e');
    }
  }

  @override
  Future<bool> login(String appId, {String? token}) async {
    if (_client == null) return false;
    try {
      final (status, _) = await _client!.login(token ?? appId);
      if (status.error == true) {
        LogService().log('RTM', '登录失败: ${status.reason}');
        return false;
      }
      LogService().log('RTM', '登录成功');
      return true;
    } catch (e) {
      LogService().log('RTM', '登录异常: $e');
      return false;
    }
  }

  @override
  Future<void> logout() async {
    if (_client == null) return;
    try {
      final (status, _) = await _client!.logout();
      if (status.error == true) {
        LogService().log('RTM', '登出失败: ${status.reason}');
      } else {
        LogService().log('RTM', '登出成功');
      }
    } catch (e) {
      LogService().log('RTM', '登出异常: $e');
    }
  }

  @override
  Future<bool> subscribe(String channel) async {
    if (_client == null) return false;
    try {
      final (status, _) = await _client!.subscribe(channel);
      if (status.error == true) {
        LogService().log('RTM', '订阅失败: ${status.reason}');
        return false;
      }
      LogService().log('RTM', '订阅频道: $channel');
      return true;
    } catch (e) {
      LogService().log('RTM', '订阅异常: $e');
      return false;
    }
  }

  @override
  Future<void> unsubscribe(String channel) async {
    if (_client == null) return;
    try {
      final (status, _) = await _client!.unsubscribe(channel);
      if (status.error == true) {
        LogService().log('RTM', '取消订阅失败: ${status.reason}');
      } else {
        LogService().log('RTM', '取消订阅: $channel');
      }
    } catch (e) {
      LogService().log('RTM', '取消订阅异常: $e');
    }
  }

  @override
  Future<bool> publish(String channel, String message) async {
    if (_client == null) return false;
    try {
      final (status, _) = await _client!.publish(channel, message);
      if (status.error == true) {
        LogService().log('RTM', '发布失败: ${status.reason}');
        return false;
      }
      return true;
    } catch (e) {
      LogService().log('RTM', '发布异常: $e');
      return false;
    }
  }

  @override
  Future<int> getOnlineCount(String channel) async {
    if (_presence == null) return 0;
    try {
      final (status, result) = await _presence!.getOnlineUsers(
        channel,
        RtmChannelType.message,
      );
      if (status.error == true || result == null) return 0;
      return result.count;
    } catch (e) {
      LogService().log('RTM', '获取在线用户数异常: $e');
      return 0;
    }
  }

  @override
  Future<List<String>> getOnlineIds(String channel) async {
    if (_presence == null) return [];
    try {
      final (status, result) = await _presence!.getOnlineUsers(
        channel,
        RtmChannelType.message,
      );
      if (status.error == true || result == null) return [];
      return result.userStateList
          .map((u) => u.userId ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      LogService().log('RTM', '获取在线用户ID异常: $e');
      return [];
    }
  }

  @override
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    if (_storage == null) {
      LogService().log('RTM', '⚠️ setChannelMetadata: _storage is null, skip');
      return 'storage_null';
    }
    try {
      final items = metadata.entries
          .map((e) => MetadataItem(key: e.key, value: e.value))
          .toList();
      final totalLen = metadata.entries.fold<int>(
          0, (s, e) => s + e.key.length + e.value.length);
      LogService().log(
          'RTM', 'setChannelMetadata: keys=${metadata.keys.toList()}, totalLen=$totalLen');
      final (status, _) = await _storage!.setChannelMetadata(
        channelName,
        RtmChannelType.message,
        items,
      );
      LogService().log(
          'RTM', 'setChannelMetadata result: error=${status.error}, reason=${status.reason}');
      if (status.error == true) {
        return 'error:${status.reason}';
      }
      return 'ok,${metadata.length}keys,${totalLen}chars';
    } catch (e) {
      LogService().log('RTM', '设置频道元数据异常: $e');
      return 'exception:$e';
    }
  }

  @override
  Future<(Map<String, String>, String)> getChannelMetadata(
      String channelName) async {
    final empty = <String, String>{};
    if (_storage == null) {
      LogService().log('RTM', '⚠️ getChannelMetadata: _storage is null');
      return (empty, 'storage_null');
    }
    try {
      final (status, result) = await _storage!.getChannelMetadata(
        channelName,
        RtmChannelType.message,
      );
      if (status.error == true || result == null) {
        return (empty, 'error:${status.reason}');
      }
      final data = result.data;
      if (data.items == null || data.items!.isEmpty) {
        return (empty, 'ok,0items');
      }
      final map = <String, String>{};
      for (final item in data.items!) {
        if (item.key != null && item.value != null) {
          map[item.key!] = item.value!;
        }
      }
      return (map, 'ok,${map.length}items,keys=${map.keys.toList()}');
    } catch (e) {
      LogService().log('RTM', '读取频道元数据异常: $e');
      return (empty, 'exception:$e');
    }
  }

  Future<void> _releaseClient() async {
    if (_client != null) {
      try {
        await _client!.release();
      } catch (_) {}
      _client = null;
      _storage = null;
      _presence = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _releaseClient();
    await _messageController.close();
    await _presenceController.close();
  }
}
