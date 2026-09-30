import 'dart:async';
import 'dart:convert';

import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend_factory.dart';

/// 房间同步信令门面：JSON 协议组装与事件分发保持不变，
/// 传输层按平台委托给 [RtmBackend]（agora_rtm / Windows 插件 / 降级）。
class RtmService {
  RtmService({RtmBackend? backend, Duration? initializeTimeout})
      : _backend = backend ?? createRtmBackend(),
        _initializeTimeout = initializeTimeout ?? const Duration(seconds: 15) {
    _bindBackend();
  }

  final RtmBackend _backend;
  final Duration _initializeTimeout;
  String? _currentUserId;
  String? _currentChannelId;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController.broadcast();

  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  bool get isConnected => _backend.isReady;

  /// 当前平台是否支持房间同步信令。
  bool get isSupported => _backend.isSupported;

  void _bindBackend() {
    _messageSubscription = _backend.messageStream.listen((event) {
      try {
        final raw = '${event['message']}';
        final data = jsonDecode(raw) as Map<String, dynamic>;
        LogService().log(
            'RTM', '收到消息 type=${data['type']}, userId=${data['userId']}');
        _messageController.add(data);
      } catch (e) {
        LogService().log('RTM', '消息解析失败: $e');
      }
    });
    _presenceSubscription = _backend.presenceStream.listen((event) {
      _presenceController.add({
        'type': event['type'],
        'publisher': event['publisher'],
      });
    });
  }

  Future<void> initialize({
    required String appId,
    required String userId,
  }) async {
    _currentUserId = userId;
    // 超时兜底：底层平台通道/插件万一挂起，也不能让房间同步入口永久卡死
    await _backend.initialize(appId: appId, userId: userId).timeout(
      _initializeTimeout,
      onTimeout: () {
        LogService().log('RTM', 'initialize 超时(${_initializeTimeout.inSeconds}s)');
      },
    );
  }

  Future<bool> login(String appId, {String? token}) async {
    return _backend.login(appId, token: token);
  }

  Future<bool> subscribe(String channelName) async {
    final ok = await _backend.subscribe(channelName);
    if (ok) {
      _currentChannelId = channelName;
    }
    return ok;
  }

  Future<void> unsubscribe(String channelName) async {
    await _backend.unsubscribe(channelName);
    _currentChannelId = null;
  }

  // Channel metadata: 设置频道元数据，返回诊断字符串
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    return _backend.setChannelMetadata(
      channelName: channelName,
      metadata: metadata,
    );
  }

  // Channel metadata: 读取频道元数据，返回 (data, diagnostic)
  Future<(Map<String, String>, String)> getChannelMetadata(
      String channelName) async {
    return _backend.getChannelMetadata(channelName);
  }

  // 元数据自检：写入测试 key → 读回 → 返回诊断字符串
  Future<String> testMetadata(String channelName) async {
    const testKey = 'test_ping';
    final testValue = '${DateTime.now().millisecondsSinceEpoch}';
    LogService().log('RTM', 'testMetadata: 写入 $testKey=$testValue');

    final writeDiag = await setChannelMetadata(
      channelName: channelName,
      metadata: {testKey: testValue},
    );
    LogService().log('RTM', 'testMetadata 写入诊断: $writeDiag');

    if (writeDiag.startsWith('error') ||
        writeDiag.startsWith('storage_null') ||
        writeDiag.startsWith('exception') ||
        writeDiag.startsWith('unsupported')) {
      return '写入失败: $writeDiag';
    }

    final (readData, readDiag) = await getChannelMetadata(channelName);
    LogService().log('RTM', 'testMetadata 读取诊断: $readDiag');

    final readValue = readData[testKey];
    if (readValue == testValue) {
      return '✅ 自检通过: 写=$writeDiag, 读=$readDiag';
    } else if (readValue != null) {
      return '⚠️ 值不匹配: 写=$testValue, 读=$readValue';
    } else {
      return '❌ 读回为空: 写=$writeDiag, 读=$readDiag, keys=${readData.keys.toList()}';
    }
  }

  // Presence: 获取在线用户数
  Future<int> getOnlineUserCount(String channelName) async {
    return _backend.getOnlineCount(channelName);
  }

  Future<List<String>> getOnlineUserIds(String channelName) async {
    return _backend.getOnlineIds(channelName);
  }

  // 发送 RTM 消息
  Future<void> sendHeartbeat({
    required double position,
    required bool playing,
    required double rate,
  }) async {
    if (!_backend.isReady || _currentChannelId == null) return;

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
    String? token,
  }) async {
    if (!_backend.isReady || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': action,
      if (position != null) 'position': position,
      if (rate != null) 'rate': rate,
      if (episodeIndex != null) 'episodeIndex': episodeIndex,
      if (itemId != null) 'itemId': itemId,
      if (playUrl != null) 'playUrl': playUrl,
      if (token != null) 'token': token,
    };

    await _publishMessage(message);
  }

  Future<void> sendJoinLeave({
    required String action,
    required String userName,
  }) async {
    if (!_backend.isReady || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': action,
      'userName': userName,
    };

    await _publishMessage(message);
  }

  Future<void> sendRequestRoomInfo() async {
    if (!_backend.isReady || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': AppConstants.actionRequestRoomInfo,
    };

    await _publishMessage(message);
  }

  Future<void> sendAddResource({
    required String itemId,
    required String name,
    required String poster,
    required bool isSeries,
    String seriesName = '',
    List<Map<String, dynamic>>? episodes,
    String? mediaSourceId,
    String? serverId,
  }) async {
    if (!_backend.isReady || _currentChannelId == null) return;

    final message = {
      'type': AppConstants.msgTypeCommand,
      'userId': _currentUserId,
      'action': AppConstants.actionAddResource,
      'itemId': itemId,
      'name': name,
      'poster': poster,
      'isSeries': isSeries,
      'seriesName': seriesName,
      if (episodes != null) 'episodes': episodes,
      if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
      if (serverId != null) 'serverId': serverId,
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
    List<String>? episodeSeriesNames,
    List<String?>? episodeMediaSourceIds,
    String? playUrl,
    String? token,
    List<Map<String, dynamic>>? subtitleStreams,
    List<Map<String, dynamic>>? audioStreams,
    Map<String, dynamic>? videoStream,
    int? defaultAudioStreamIndex,
    String? serverId,
  }) async {
    if (!_backend.isReady) return;

    final message = {
      'type': AppConstants.msgTypeRoomInfo,
      'userId': _currentUserId,
      if (serverId != null) 'serverId': serverId,
      if (mediaItemId != null) 'mediaItemId': mediaItemId,
      if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
      if (mediaItemName != null) 'mediaItemName': mediaItemName,
      if (seriesName != null) 'seriesName': seriesName,
      if (episodeIds != null) 'episodeIds': episodeIds,
      if (episodeNames != null) 'episodeNames': episodeNames,
      if (episodeSeasons != null) 'episodeSeasons': episodeSeasons,
      if (episodeNumbers != null) 'episodeNumbers': episodeNumbers,
      if (episodePosters != null) 'episodePosters': episodePosters,
      if (episodeSeriesNames != null) 'episodeSeriesNames': episodeSeriesNames,
      if (episodeMediaSourceIds != null)
        'episodeMediaSourceIds': episodeMediaSourceIds,
      if (playUrl != null) 'playUrl': playUrl,
      if (token != null) 'token': token,
      if (subtitleStreams != null) 'subtitleStreams': subtitleStreams,
      if (audioStreams != null) 'audioStreams': audioStreams,
      if (videoStream != null) 'videoStream': videoStream,
      if (defaultAudioStreamIndex != null)
        'defaultAudioStreamIndex': defaultAudioStreamIndex,
    };

    try {
      final encoded = jsonEncode(message);
      LogService().log('RTM',
          'sendRoomInfo size=${encoded.length} bytes, episodes=${episodeIds?.length ?? 0}');
      final ok = await _backend.publish(channelName, encoded);
      if (!ok) {
        LogService().log('RTM', '发送房间信息失败');
      }
    } catch (e) {
      LogService().log('RTM', '发送房间信息异常: $e');
    }
  }

  Future<void> _publishMessage(Map<String, dynamic> message) async {
    if (!_backend.isReady || _currentChannelId == null) return;

    try {
      final encoded = jsonEncode(message);
      LogService()
          .log('RTM', '发布消息 type=${message['type']}, size=${encoded.length} bytes');
      final ok = await _backend.publish(_currentChannelId!, encoded);
      if (!ok) {
        LogService().log('RTM', '发布失败');
      }
    } catch (e) {
      LogService().log('RTM', '发布异常: $e');
    }
  }

  Future<void> logout() async {
    await _backend.logout();
  }

  void dispose() {
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel();
    _messageController.close();
    _presenceController.close();
    _backend.dispose();
  }
}
