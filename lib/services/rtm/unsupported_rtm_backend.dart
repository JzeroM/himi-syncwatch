import 'dart:async';

import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';

/// 不支持的平台（macOS / Linux）：所有操作快速失败，
/// 避免 agora_rtm 缺原生实现导致的静默挂起。
class UnsupportedRtmBackend implements RtmBackend {
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController.broadcast();

  @override
  bool get isSupported => false;

  @override
  bool get isReady => false;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;

  @override
  Future<void> initialize({required String appId, required String userId}) async {
    LogService().log('RTM', '当前平台不支持房间同步信令');
  }

  @override
  Future<bool> login(String appId, {String? token}) async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<bool> subscribe(String channel) async => false;

  @override
  Future<void> unsubscribe(String channel) async {}

  @override
  Future<bool> publish(String channel, String message) async => false;

  @override
  Future<int> getOnlineCount(String channel) async => 0;

  @override
  Future<List<String>> getOnlineIds(String channel) async => const [];

  @override
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async =>
      'unsupported';

  @override
  Future<(Map<String, String>, String)> getChannelMetadata(
          String channelName) async =>
      (const <String, String>{}, 'unsupported');

  @override
  Future<void> dispose() async {
    await _messageController.close();
    await _presenceController.close();
  }
}
