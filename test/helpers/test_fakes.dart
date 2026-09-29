import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 不触碰平台通道的设置通知器（覆写落盘）。
class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings initial = const AppSettings()]) {
    state = initial;
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> persist() async {}
}

/// 不触碰平台通道的声网配置通知器。
class FakeAgoraConfigNotifier extends AgoraConfigNotifier {
  FakeAgoraConfigNotifier([AgoraConfigModel? initial]) {
    if (initial != null) {
      state = initial;
    }
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> save(AgoraConfigModel config) async {
    state = config;
  }

  @override
  Future<void> clear() async {
    state = null;
  }
}

/// 内存版 Emby 认证服务（不访问 FlutterSecureStorage）。
class FakeEmbyAuthService extends EmbyAuthService {
  FakeEmbyAuthService({
    List<String> serverIds = const [],
    this.sessions = const {},
  }) : _serverIds = serverIds;

  final List<String> _serverIds;

  /// serverId → 会话 JSON（EmbyServerConfig.fromJson 可解析）。
  final Map<String, Map<String, dynamic>> sessions;

  String? selectedServerId;

  @override
  Future<List<String>> listServerIds() async => _serverIds;

  @override
  Future<String?> loadSelectedServerId() async => selectedServerId;

  @override
  Future<void> saveSelectedServerId(String configId) async {
    selectedServerId = configId;
  }

  @override
  Future<Map<String, dynamic>?> loadSession(String serverId) async =>
      sessions[serverId];

  @override
  Future<void> saveSession({
    required String serverId,
    required String serverUrl,
    required String serverName,
    required String userId,
    required String username,
    required String id,
    required String accessToken,
  }) async {}

  @override
  Future<void> deleteSession(String serverId) async {}
}

/// 不发起真实网络请求的 Emby 服务。
class FakeEmbyService extends EmbyService {
  @override
  Future<MediaItem?> getItemDetails(String id) async => null;

  @override
  Future<List<LibraryFolder>> getLibraries() async => [];
}
