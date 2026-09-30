/// RTM 后端抽象：RtmService 门面与具体平台实现（agora_rtm 插件 /
/// Windows C++ 插件 / 不支持的桌面平台）解耦。
///
/// 事件流约定：
/// - messageStream: `{publisher: String, message: String(原始 JSON 文本)}`
/// - presenceStream: `{type: RtmPresenceEventType, publisher: String}`
abstract class RtmBackend {
  /// 当前平台是否支持房间同步信令。
  bool get isSupported;

  /// 客户端是否已创建就绪。
  bool get isReady;

  Stream<Map<String, dynamic>> get messageStream;
  Stream<Map<String, dynamic>> get presenceStream;

  Future<void> initialize({required String appId, required String userId});

  Future<bool> login(String appId, {String? token});

  Future<void> logout();

  Future<bool> subscribe(String channel);

  Future<void> unsubscribe(String channel);

  Future<bool> publish(String channel, String message);

  /// 在线人数；失败返回 0。
  Future<int> getOnlineCount(String channel);

  /// 在线用户 ID；失败返回空列表。
  Future<List<String>> getOnlineIds(String channel);

  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  });

  Future<(Map<String, String>, String)> getChannelMetadata(String channelName);

  Future<void> dispose();
}
