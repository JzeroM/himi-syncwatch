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

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool get isConnected => _client != null;

  Future<void> initialize({
    required String appId,
    required String userId,
  }) async {
    _currentUserId = userId;

    final rtmConfig = RtmConfig(
      areaCode: {RtmAreaCode.cn},
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
              final data = jsonDecode(utf8.decode(event.message!));
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
        },
      );
    } catch (e) {
      print('[RTM] 初始化异常: $e');
    }
  }

  Future<void> login(String appId, {String? token}) async {
    if (_client == null) return;

    try {
      final (status, _) = await _client!.login(token ?? appId);
      if (status.error == true) {
        print('[RTM] 登录失败: ${status.reason}');
      } else {
        print('[RTM] 登录成功');
      }
    } catch (e) {
      print('[RTM] 登录异常: $e');
    }
  }

  Future<void> subscribe(String channelName) async {
    if (_client == null) return;

    _currentChannelId = channelName;

    try {
      final (status, _) = await _client!.subscribe(channelName);
      if (status.error == true) {
        print('[RTM] 订阅失败: ${status.reason}');
      } else {
        print('[RTM] 订阅频道: $channelName');
      }
    } catch (e) {
      print('[RTM] 订阅异常: $e');
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
    if (_storage == null) return;

    try {
      final items = metadata.entries
          .map((e) => MetadataItem(key: e.key, value: e.value))
          .toList();
      final (status, _) = await _storage!.setChannelMetadata(
        channelName,
        RtmChannelType.message,
        items,
      );
      if (status.error == true) {
        print('[RTM] 设置频道元数据失败: ${status.reason}');
      }
    } catch (e) {
      print('[RTM] 设置频道元数据异常: $e');
    }
  }

  // Channel metadata: 读取频道元数据
  Future<Map<String, String>> getChannelMetadata(String channelName) async {
    if (_storage == null) return {};

    try {
      final (status, result) = await _storage!.getChannelMetadata(
        channelName,
        RtmChannelType.message,
      );
      if (status.error == true || result == null) {
        return {};
      }
      final data = result.data;
      if (data.items == null) return {};
      return {
        for (final item in data.items!)
          if (item.key != null && item.value != null) item.key!: item.value!,
      };
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
  }) async {
    await setChannelMetadata(
      channelName: channelName,
      metadata: {
        'playUrl': playUrl,
        'itemId': itemId,
        if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
        if (currentEpisodeIndex != null)
          'currentEpisodeIndex': '$currentEpisodeIndex',
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

  Future<void> sendRoomInfo({
    required String channelName,
    required String seriesName,
    required List<String> episodeIds,
    required List<String> episodeNames,
    required List<int> episodeSeasons,
    required List<int> episodeNumbers,
    required List<String> episodePosters,
  }) async {
    if (_client == null) return;

    final message = {
      'type': AppConstants.msgTypeRoomInfo,
      'userId': _currentUserId,
      'seriesName': seriesName,
      'episodeIds': episodeIds,
      'episodeNames': episodeNames,
      'episodeSeasons': episodeSeasons,
      'episodeNumbers': episodeNumbers,
      'episodePosters': episodePosters,
    };

    try {
      final (status, _) = await _client!.publish(
        channelName,
        jsonEncode(message),
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
      final (status, _) = await _client!.publish(
        _currentChannelId!,
        jsonEncode(message),
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
    logout();
    _client?.release();
    _client = null;
    _storage = null;
    _presence = null;
  }
}
