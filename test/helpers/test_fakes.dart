import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
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

  /// persist 调用计数（验证 update 确实触发落盘）。
  int persistCount = 0;

  @override
  Future<void> load() async {}

  @override
  Future<void> persist() async => persistCount++;
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
  FakeEmbyService({
    this.item,
    this.similar = const [],
    this.libraries = const [],
    this.items = const [],
    this.itemsByParent = const {},
    this.searchResults = const [],
    this.itemCounts,
    this.seasons = const [],
    this.favoriteItems = const [],
  });

  final MediaItem? item;
  final List<MediaItem> similar;
  final List<LibraryFolder> libraries;
  final List<MediaItem> items;

  /// 收藏页数据源（getFavoriteItems）；测试按类型预置。
  final List<MediaItem> favoriteItems;

  /// setFavorite 收到的调用记录（id + 目标收藏态）。
  final List<({String id, bool favorite})> favoriteCalls = [];

  /// setFavorite 返回值（false 模拟失败 → 详情页应回滚）。
  bool favoriteSetResult = true;

  /// 按 parentId 精确返回（用于模拟空媒体库）；未命中的库回退到 [items]。
  final Map<String, List<MediaItem>> itemsByParent;

  /// searchItems 返回结果（聚合搜索测试用）。
  final List<MediaItem> searchResults;

  /// getItemCounts 返回结果；null = 统计失败（首页不渲染底部面板）。
  final MediaCounts? itemCounts;

  /// getSeasons 返回结果（剧集详情页分季兜底测试用）。
  final List<MediaItem> seasons;

  /// 最近一次 getItems 收到的 fields（断言 AlternateMediaSources 等
  /// Emby 4.9.x 非管理员多版本字段透传用）。
  String? lastGetItemsFields;

  /// 最近一次 getItems 收到的 sortBy/sortOrder（首页"最近添加"排序断言用）。
  String? lastGetItemsSortBy;
  String? lastGetItemsSortOrder;

  @override
  Future<List<MediaItem>> getSeasons(String seriesId) async => seasons;

  @override
  Future<List<MediaItem>> getFavoriteItems() async => favoriteItems;

  @override
  Future<bool> setFavorite(String itemId, bool favorite) async {
    favoriteCalls.add((id: itemId, favorite: favorite));
    return favoriteSetResult;
  }

  @override
  Future<MediaCounts?> getItemCounts() async => itemCounts;

  @override
  Future<List<MediaItem>> searchItems(String query) async => searchResults;

  @override
  Future<MediaItem?> getItemDetails(String id) async => item;

  @override
  Future<List<LibraryFolder>> getLibraries() async => libraries;

  @override
  Future<List<MediaItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? fields,
    String? sortBy,
    String? sortOrder,
  }) async {
    lastGetItemsFields = fields;
    lastGetItemsSortBy = sortBy;
    lastGetItemsSortOrder = sortOrder;
    return (parentId != null && itemsByParent.containsKey(parentId))
        ? itemsByParent[parentId]!
        : items;
  }

  @override
  Future<List<MediaItem>> getSimilarItems(String itemId,
          {int limit = 10}) async =>
      similar;

  // ---- 添加服务器流程（pingServer / authenticate）----
  Map<String, dynamic> pingResult = const {
    'ServerName': '测试服务器',
    'Id': 'srv_ping_1',
  };
  Object? pingError;
  Map<String, dynamic>? authResult;
  Object? authError;
  String? lastAuthUsername;
  String? lastAuthPassword;

  @override
  Future<Map<String, dynamic>> pingServer(String serverUrl) async {
    final err = pingError;
    if (err != null) throw err;
    return pingResult;
  }

  @override
  Future<Map<String, dynamic>> authenticate({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    lastAuthUsername = username;
    lastAuthPassword = password;
    final err = authError;
    if (err != null) throw err;
    return authResult ??
        const {
          'User': {'Id': 'user_1'},
          'AccessToken': 'token_1',
          'ServerId': 'srv_ping_1',
        };
  }
}
