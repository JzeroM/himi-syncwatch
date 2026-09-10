import 'dart:async';
import 'dart:convert';
import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_syncwatch/core/constants.dart';

class RtmService {
  RtmClient? _client;
  RtmStorage? _storage;
  RtmPresence? _presence;
  String? _currentUserId;
  String? _currentChannelId;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  bool get isConnected => _client != null;

  Future<void> initialize({
    required String appId,
    required String userId,
  }) async {
    _currentUserId = userId;

    // 释放旧 client
    if (_client != null) {
      try {
        await _client!.release();
      } catch (_) {}
      _client = null;
      _storage = null;
      _presence = null;
    }

    final rtmConfig = RtmConfig(
      areaCode: {RtmAreaCode.glob},
      useStringUserId: true,
      heartbeatInterval: 5,
      presenceTimeout: 300,
    );

    try {
      final (status, client) = await RTM(appId, userId, config: rtmConfig);

      if (status.error == true) {
        print('[RTM] 初始化失败: ${status.reason}');
        return;
      }

      _client = client;
      _storage = client.getStorage();
      _presence = client.getPresence();
      print('[RTM] 初始化成功, userId: $userId');

      _client?.addListener(
        message: (event) {
          try {
            if (event.message != null) {
              final raw = utf8.decode(event.message!);
              print('[RTM] 收到原始消息: ${raw.length} bytes');
              final data = jsonDecode(raw);
              print('[RTM] 收到消息 type=${data['type']}, userId=${data['userId']}');
              _messageController.add(data);
            }
          } catch (e) {
            print('[RTM] 消息解析失败: $e');
          }
        },
        linkState: (event) {
          print('[RTM] 连接状态: ${event.currentState}');
        },
        presence: (event) {
          print('[RTM] 成员变化: ${event.type}');
          _presenceController.add({'type': event.type});
        },
      );
    } catch (e) {
      print('[RTM] 初始化异常: $e');
    }
  }

  Future<bool> login(String appId, {String? token}) async {
    if (_client == null) return false;

    try {
      final (status, _) = await _client!.login(token ?? appId);
      if (status.error == true) {
        print('[RTM] 登录失败: ${status.reason}');
        return false;
      }
      print('[RTM] 登录成功');
      return true;
    } catch (e) {
      print('[RTM] 登录异常: $e');
      return false;
    }
  }

  Future<bool> subscribe(String channelName) async {
    if (_client == null) return false;

    _currentChannelId = channelName;

    try {
      final (status, _) = await _client!.subscribe(channelName);
      if (status.error == true) {
        print('[RTM] 订阅失败: ${status.reason}');
        return false;
      } else {
        print('[RTM] 订阅频道: $channelName');
        return true;
      }
    } catch (e) {
      print('[RTM] 订阅异常: $e');
      return false;
    }
  }

  Future<void> unsubscribe(String channelName) async {
    if (_client == null) return;

    try {
      final (status, _) = await _client!.unsubscribe(channelName);
      if (status.error == true) {
        print('[RTM] 取消订阅失败: ${status.reason}');
      } else {
        print('[RTM] 取消订阅: $channelName');
        _currentChannelId = null;
      }
    } catch (e) {
      print('[RTM] 取消订阅异常: $e');
    }
  }

  // Channel metadata: 设置频道元数据
  Future<void> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    if (_storage == null) {
      print('[RTM] ⚠️ setChannelMetadata: _storage is null, skip');
      return;
    }

    try {
      final items = metadata.entries
          .map((e) => MetadataItem(key: e.key, value: e.value))
          .toList();
      final totalLen = metadata.entries.fold<int>(0, (s, e) => s + e.key.length + e.value.length);
      print('[RTM] setChannelMetadata: keys=${metadata.keys.toList()}, totalLen=$totalLen');
      final (status, result) = await _storage!.setChannelMetadata(
        channelName,
        RtmChannelType.message,
        items,
      );
      print('[RTM] setChannelMetadata result: error=${status.error}, reason=${status.reason}');
      if (result != null) {
        print('[RTM] setChannelMetadata result: channelName=${result.channelName}, channelType=${result.channelType}');
      }
    } catch (e) {
      print('[RTM] 设置频道元数据异常: $e');
    }
  }

  // Channel metadata: 读取频道元数据
  Future<Map<String, String>> getChannelMetadata(String channelName) async {
    if (_storage == null) {
      print('[RTM] ⚠️ getChannelMetadata: _storage is null');
      return {};
    }

    try {
      final (status, result) = await _storage!.getChannelMetadata(
        channelName,
        RtmChannelType.message,
      );
      print('[RTM] getChannelMetadata: error=${status.error}, reason=${status.reason}');
      if (status.error == true || result == null) {
        print('[RTM] getChannelMetadata: result is null or error');
        return {};
      }
      final data = result.data;
      print('[RTM] getChannelMetadata: majorRevision=${data.majorRevision}, itemCount=${data.itemCount}, items=${data.items?.length ?? 0}');
      if (data.items == null || data.items!.isEmpty) {
        print('[RTM] getChannelMetadata: items 为空');
        return {};
      }
      final map = <String, String>{};
      for (final item in data.items!) {
        print('[RTM]   item: key=${item.key}, valueLen=${item.value?.length ?? 0}, author=${item.authorUserId}, revision=${item.revision}');
        if (item.key != null && item.value != null) {
          map[item.key!] = item.value!;
        }
      }
      print('[RTM] getChannelMetadata: 返回 ${map.length} 个 key: ${map.keys.toList()}');
      return map;
    } catch (e) {
      print('[RTM] 读取频道元数据异常: $e');
      return {};
    }
  }

  // Presence: 获取在线用户数
  Future<int> getOnlineUserCount(String channelName) async {
    if (_presence == null) return 0;

    try {
      final (status, result) = await _presence!.getOnlineUsers(
        channelName,
        RtmChannelType.message,
      );
      if (status.error == true || result == null) {
        return 0;
      }
      return result.count;
    } catch (e) {
      print('[RTM] 获取在线用户数异常: $e');
      return 0;
    }
  }

  // 发布播放信息到频道元数据
  Future<void> publishPlayInfo({
    required String channelName,
    required String playUrl,
    required String itemId,
    String? mediaSourceId,
    int? currentEpisodeIndex,
    String? token,
  }) async {
    await setChannelMetadata(
      channelName: channelName,
      metadata: {
        'playUrl': playUrl,
        'itemId': itemId,
        if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
        if (currentEpisodeIndex != null)
          'currentEpisodeIndex': '$currentEpisodeIndex',
        if (token != null) 'token': token,
      },
    );
  }

  // 发送 RTM 消息
  Future<void> sendHeartbeat({
    required double position,
    required bool playing,
    required double rate,
  }) async {
    if (_client == null || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeHeartbeat,
      'userId': _currentUserId,
      'position': position,
      'playing': playing,
      'rate': rate,
      'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    await _publishMessage(message);
  }

  Future<void> sendCommand({
    required String action,
    double? position,
    double? rate,
    int? episodeIndex,
    String? itemId,
    String? playUrl,
  }) async {
    if (_client == null || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': action,
      if (position != null) 'position': position,
      if (rate != null) 'rate': rate,
      if (episodeIndex != null) 'episodeIndex': episodeIndex,
      if (itemId != null) 'itemId': itemId,
      if (playUrl != null) 'playUrl': playUrl,
    };

    await _publishMessage(message);
  }

  Future<void> sendJoinLeave({
    required String action,
    required String userName,
  }) async {
    if (_client == null || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': action,
      'userName': userName,
    };

    await _publishMessage(message);
  }

  Future<void> sendRequestRoomInfo() async {
    if (_client == null || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': AppConstants.actionRequestRoomInfo,
    };

    await _publishMessage(message);
  }

  Future<void> sendRoomInfo({
    required String channelName,
    String? mediaItemId,
    String? mediaSourceId,
    String? mediaItemName,
    String? seriesName,
    List<String>? episodeIds,
    List<String>? episodeNames,
    List<int>? episodeSeasons,
    List<int>? episodeNumbers,
    List<String>? episodePosters,
    String? playUrl,
  }) async {
    if (_client == null) return;

    final message = {
      'type': AppConstants.msgTypeRoomInfo,
      'userId': _currentUserId,
      if (mediaItemId != null) 'mediaItemId': mediaItemId,
      if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
      if (mediaItemName != null) 'mediaItemName': mediaItemName,
      if (seriesName != null) 'seriesName': seriesName,
      if (episodeIds != null) 'episodeIds': episodeIds,
      if (episodeNames != null) 'episodeNames': episodeNames,
      if (episodeSeasons != null) 'episodeSeasons': episodeSeasons,
      if (episodeNumbers != null) 'episodeNumbers': episodeNumbers,
      if (episodePosters != null) 'episodePosters': episodePosters,
      if (playUrl != null) 'playUrl': playUrl,
    };

    try {
      final encoded = jsonEncode(message);
      print('[RTM] sendRoomInfo size=${encoded.length} bytes, episodes=${episodeIds?.length ?? 0}');
      final (status, _) = await _client!.publish(
        channelName,
        encoded,
      );
      if (status.error == true) {
        print('[RTM] 发送房间信息失败: ${status.reason}');
      }
    } catch (e) {
      print('[RTM] 发送房间信息异常: $e');
    }
  }

  Future<void> _publishMessage(Map<String, dynamic> message) async {
    if (_client == null || _currentChannelId == null) return;

    try {
      final encoded = jsonEncode(message);
      print('[RTM] 发布消息 type=${message['type']}, size=${encoded.length} bytes');
      final (status, _) = await _client!.publish(
        _currentChannelId!,
        encoded,
      );

      if (status.error == true) {
        print('[RTM] 发布失败: ${status.reason}');
      }
    } catch (e) {
      print('[RTM] 发布异常: $e');
    }
  }

  Future<void> logout() async {
    if (_client == null) return;

    try {
      final (status, _) = await _client!.logout();
      if (status.error == true) {
        print('[RTM] 登出失败: ${status.reason}');
      } else {
        print('[RTM] 登出成功');
      }
    } catch (e) {
      print('[RTM] 登出异常: $e');
    }
  }

  void dispose() {
    _messageController.close();
    _presenceController.close();
    logout();
    _client?.release();
    _client = null;
    _storage = null;
    _presence = null;
  }
}
