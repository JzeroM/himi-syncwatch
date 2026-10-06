import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/media_item.dart';

class EmbyService {
  late Dio _dio;
  String? _serverUrl;
  String? _accessToken;
  String? _userId;
  String? _serverId;
  String? _deviceId;

  EmbyService() {
    _dio = Dio();
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      return client;
    };
  }

  String? get serverUrl => _serverUrl;
  String? get accessToken => _accessToken;
  String? get serverId => _serverId;

  void configure({
    required String serverUrl,
    required String accessToken,
    required String userId,
    required String serverId,
    String deviceId = 'himi-001',
  }) {
    _serverUrl = serverUrl;
    _accessToken = accessToken;
    _userId = userId;
    _serverId = serverId;
    _deviceId = deviceId;

    _dio.options.baseUrl = serverUrl;
    _dio.options.headers['X-Emby-Token'] = accessToken;
    _dio.options.headers['X-Emby-Authorization'] = _buildAuthHeader();
  }

  String _buildAuthHeader() {
    return 'Emby Client="HIMI", Device="Desktop", '
        'DeviceId="$_deviceId", Version="1.0.0", '
        'UserId="$_userId", Token="$_accessToken", '
        'ServerId="$_serverId"';
  }

  Future<Map<String, dynamic>> pingServer(String serverUrl) async {
    final dio = Dio(BaseOptions(
      baseUrl: serverUrl,
      connectTimeout: const Duration(seconds: 5),
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      return client;
    };

    final response = await dio.get('/System/Info/Public');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> authenticate({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final dio = Dio(BaseOptions(baseUrl: serverUrl));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      return client;
    };

    dio.options.headers['X-Emby-Authorization'] =
        'Emby Client="HIMI", Device="Desktop", '
        'DeviceId="$deviceId", Version="1.0.0"';

    final response = await dio.post(
      '/Users/authenticatebyname',
      data: {'Username': username, 'Pw': password},
    );

    return response.data as Map<String, dynamic>;
  }

  Future<MediaItem?> validateToken() async {
    try {
      final response = await _dio.get('/Users/$_userId');
      return MediaItem.fromJson(response.data, serverUrl: _serverUrl);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      return null;
    }
  }

  Future<List<MediaItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? fields,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final response = await _dio.get(
        '/Items',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          if (parentId != null) 'ParentId': parentId,
          if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
          if (limit != null) 'Limit': limit,
          if (startIndex != null) 'StartIndex': startIndex,
          if (sortBy != null) 'SortBy': sortBy,
          if (sortOrder != null) 'SortOrder': sortOrder,
          'Recursive': true,
          'Fields': fields ??
              // AlternateMediaSources：Emby 4.9.x 批量端点对非管理员每条
              // 只回 1 个 MediaSource，需显式请求才返回全部版本
              'ImageTags,PrimaryImageAspectRatio,ProductionYear,Overview,Genres,MediaStreams,MediaSources,AlternateMediaSources',
          'ImageTypeLimit': 1,
        },
      );

      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  /// 获取剧集的季列表（`GET /Shows/{seriesId}/Seasons`）。
  ///
  /// 返回的季为 `Type:Season` 的 MediaItem：`childCount` = 该季集数，
  /// `posterUrl` 来自 `ImageTags.Primary`（季海报）。失败返回空列表，
  /// 调用方应从已有集按 `parentIndexNumber` 分组兜底。
  Future<List<MediaItem>> getSeasons(String seriesId) async {
    try {
      final response = await _dio.get(
        '/Shows/$seriesId/Seasons',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'Fields': 'ImageTags,ChildCount',
          'ImageTypeLimit': 1,
        },
      );
      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  /// 统计电影 / 电视剧 / 集的总数量。
  ///
  /// 优先走专用端点 `GET /Items/Counts`（一次请求返回 MovieCount 等字段）；
  /// 老版本响应缺字段时回退为三次 `GET /Items` 读 `TotalRecordCount`
  /// （兼容旧键名 `TotalRecords`）。任何失败返回 null，不抛错、不阻塞调用方。
  Future<MediaCounts?> getItemCounts() async {
    try {
      final direct = await _countsFromEndpoint();
      if (direct != null) return direct;
      return await _countsFromItemsQuery();
    } catch (_) {
      return null;
    }
  }

  /// `GET /Items/Counts` → ItemCounts（MovieCount/SeriesCount/EpisodeCount）。
  /// 三个计数字段任一缺失则视为该端点不可用，返回 null 触发回退。
  Future<MediaCounts?> _countsFromEndpoint() async {
    try {
      final resp = await _dio.get(
        '/Items/Counts',
        queryParameters: {if (_userId != null) 'UserId': _userId},
      );
      final data = resp.data;
      if (data is! Map) return null;
      final movies = data['MovieCount'];
      final series = data['SeriesCount'];
      final episodes = data['EpisodeCount'];
      if (movies is! num || series is! num || episodes is! num) return null;
      return MediaCounts(
        movies: movies.toInt(),
        series: series.toInt(),
        episodes: episodes.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 回退：并发三次 `/Items`（Limit=1）读 TotalRecordCount（兼容 TotalRecords）。
  Future<MediaCounts?> _countsFromItemsQuery() async {
    const types = ['Movie', 'Series', 'Episode'];
    final responses = await Future.wait([
      for (final type in types)
        _dio.get('/Items', queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'Recursive': true,
          'IncludeItemTypes': type,
          'Limit': 1,
        }),
    ]);
    int countOf(int index) {
      final data = responses[index].data;
      if (data is! Map) return 0;
      final total = data['TotalRecordCount'] ?? data['TotalRecords'];
      return total is num ? total.toInt() : 0;
    }

    return MediaCounts(
      movies: countOf(0),
      series: countOf(1),
      episodes: countOf(2),
    );
  }

  Future<List<MediaItem>> getLatestItems({
    String? parentId,
    int limit = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/Users/$_userId/Items/Latest',
        queryParameters: {
          if (parentId != null) 'ParentId': parentId,
          'Limit': limit,
          'Fields': 'CommunityRating,ProductionYear,ImageTags',
          'ImageTypeLimit': 1,
        },
      );

      final items = response.data as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  Future<List<MediaItem>> getSimilarItems(String itemId,
      {int limit = 10}) async {
    try {
      final response = await _dio.get(
        '/Items/$itemId/Similar',
        queryParameters: {
          'Limit': limit,
          'Fields': 'CommunityRating,ProductionYear,IndexNumber,ImageTags',
          'ImageTypeLimit': 1,
        },
      );

      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  Future<List<MediaItem>> searchItems(String query) async {
    try {
      final response = await _dio.get(
        '/Items',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'Recursive': true,
          'IncludeItemTypes': 'Movie,Series',
          'searchTerm': query,
          'Limit': 30,
          'Fields': 'ImageTags,PrimaryImageAspectRatio,ProductionYear',
          'ImageTypeLimit': 1,
        },
      );

      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  /// 获取媒体库列表。
  ///
  /// 严格保持服务端 `/Users/{id}/Views` 返回顺序（即 Emby 服务器设定的
  /// 媒体库排序），不做任何本地排序。
  Future<List<LibraryFolder>> getLibraries() async {
    try {
      final response = await _dio.get(
        '/Users/$_userId/Views',
        queryParameters: {'Fields': 'ImageTags'},
      );
      final items = response.data['Items'] as List<dynamic>? ?? [];
      final folders = <LibraryFolder>[];
      for (final f in items) {
        final name = f['Name'] as String? ?? '';
        final itemId = (f['ItemId'] ?? f['Id'])?.toString() ?? '';
        final collectionType = f['CollectionType'] as String? ?? '';
        if (name.isNotEmpty && itemId.isNotEmpty) {
          var posterUrl =
              '$_serverUrl/Items/$itemId/Images/Primary?maxHeight=300';
          final imageTags = f['ImageTags'] as Map<String, dynamic>?;
          final primaryTag = imageTags?['Primary'] as String?;
          if (primaryTag != null && primaryTag.isNotEmpty) {
            posterUrl += '&tag=$primaryTag';
          }
          folders.add(LibraryFolder(
            id: itemId,
            name: name,
            collectionType: collectionType,
            posterUrl: posterUrl,
          ));
        }
      }
      return folders;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  Future<MediaItem?> getItemDetails(String id) async {
    try {
      final response = await _dio.get(
        '/Users/$_userId/Items/$id',
        queryParameters: {
          // ImageTags：详情页标题艺术字（ImageTags.Logo）依赖此字段
          // UserData：收藏状态（UserData.IsFavorite）
          'Fields':
              'Overview,Genres,MediaStreams,MediaSources,AlternateMediaSources,CommunityRating,OfficialRating,ProductionYear,RunTimeTicks,ImageTags,UserData,ProviderIds,ExternalUrls,Studios,Path,DateCreated',
        },
      );
      return MediaItem.fromJson(response.data, serverUrl: _serverUrl);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return null;
    }
  }

  /// 收藏 / 取消收藏：Emby `POST|DELETE /Users/{userId}/FavoriteItems/{itemId}`。
  /// 成功返回 true；失败（网络/鉴权）返回 false，由调用方回滚乐观 UI。
  Future<bool> setFavorite(String itemId, bool favorite) async {
    try {
      final path = '/Users/$_userId/FavoriteItems/$itemId';
      if (favorite) {
        await _dio.post(path);
      } else {
        await _dio.delete(path);
      }
      return true;
    } on DioException {
      return false;
    }
  }

  /// 标记已观看 / 取消已观看：
  /// Emby `POST|DELETE /Users/{userId}/PlayedItems/{itemId}`。
  /// 对剧集 id 调用即标记整部剧（Emby 会级联到其各集）。
  /// 成功返回 true；失败返回 false，由调用方回滚乐观 UI。
  Future<bool> setWatched(String itemId, bool watched) async {
    try {
      final path = '/Users/$_userId/PlayedItems/$itemId';
      if (watched) {
        await _dio.post(path);
      } else {
        await _dio.delete(path);
      }
      return true;
    } on DioException {
      return false;
    }
  }

  /// 当前服务器全部收藏条目（电影/剧集/单集），供收藏页分组展示。
  /// `Filters=IsFavorite` 服务端过滤；字段含 `UserData` 以便回显收藏态。
  /// 失败返回空列表。
  Future<List<MediaItem>> getFavoriteItems() async {
    try {
      final response = await _dio.get(
        '/Items',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'Recursive': true,
          'IncludeItemTypes': 'Movie,Series,Episode',
          'Filters': 'IsFavorite',
          'Fields':
              'UserData,ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,Overview,PremiereDate',
          'ImageTypeLimit': 1,
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        },
      );
      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  /// 当前服务器「继续观看」条目（有播放进度的电影/剧集/单集）。
  /// `GET /Users/{userId}/Items/Resume`；字段含 `UserData`（进度/百分比）。
  /// 失败返回空列表。
  Future<List<MediaItem>> getResumeItems({int limit = 12}) async {
    try {
      final response = await _dio.get(
        '/Users/$_userId/Items/Resume',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'MediaTypes': 'Video',
          'Limit': limit,
          'Fields':
              'UserData,ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,Overview,PremiereDate',
          'ImageTypeLimit': 1,
        },
      );
      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  /// 取官方 `PlaySessionId`（`POST /Items/{id}/PlaybackInfo`）。Emby 需要用它
  /// 关联播放会话，`Sessions/Playing*` 上报才能把进度写入 `UserData`（Resume）。
  /// 失败返回 null（调用方回退本地生成 id）。
  Future<String?> getPlaySessionId({
    required String itemId,
    String? mediaSourceId,
  }) async {
    try {
      final response = await _dio.post(
        '/Items/$itemId/PlaybackInfo',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          if (mediaSourceId != null && mediaSourceId.isNotEmpty)
            'MediaSourceId': mediaSourceId,
        },
        data: <String, dynamic>{},
      );
      final id = (response.data as Map?)?['PlaySessionId'];
      return id is String && id.isNotEmpty ? id : null;
    } on DioException {
      return null;
    }
  }

  /// 播放会话上报公共实现（Emby `POST /Sessions/{Playing|Playing/Progress|Playing/Stopped}`）。
  /// [positionMs] 毫秒 → `PositionTicks`（×10000）。成功返回 true。
  Future<bool> _playbackReport(
    String endpoint, {
    required String itemId,
    required String playSessionId,
    String? mediaSourceId,
    int positionMs = 0,
    bool isPaused = false,
  }) async {
    try {
      await _dio.post(
        '/Sessions/$endpoint',
        data: {
          'ItemId': itemId,
          if (mediaSourceId != null && mediaSourceId.isNotEmpty)
            'MediaSourceId': mediaSourceId,
          'PositionTicks': positionMs * 10000,
          'PlaySessionId': playSessionId,
          'CanSeek': true,
          'IsPaused': isPaused,
          'IsMuted': false,
          'PlayMethod': 'DirectStream',
        },
      );
      return true;
    } on DioException {
      return false;
    }
  }

  /// 开始播放上报（`POST /Sessions/Playing`）。
  Future<bool> reportPlaybackStart({
    required String itemId,
    required String playSessionId,
    String? mediaSourceId,
    int positionMs = 0,
  }) =>
      _playbackReport('Playing',
          itemId: itemId,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          positionMs: positionMs);

  /// 进度上报（`POST /Sessions/Playing/Progress`）。
  Future<bool> reportPlaybackProgress({
    required String itemId,
    required String playSessionId,
    String? mediaSourceId,
    int positionMs = 0,
    bool isPaused = false,
  }) =>
      _playbackReport('Playing/Progress',
          itemId: itemId,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          positionMs: positionMs,
          isPaused: isPaused);

  /// 停止上报（`POST /Sessions/Playing/Stopped`，带最终位置）。
  /// Emby 据此写入 `UserData.PlaybackPositionTicks`（≥~90% 时自动标记已观看）。
  Future<bool> reportPlaybackStopped({
    required String itemId,
    required String playSessionId,
    String? mediaSourceId,
    int positionMs = 0,
  }) =>
      _playbackReport('Playing/Stopped',
          itemId: itemId,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          positionMs: positionMs);

  String getStreamUrl(String itemId,
      {String? mediaSourceId, int? subtitleStreamIndex}) {
    if (subtitleStreamIndex != null) {
      final base = '$_serverUrl/Videos/$itemId/stream';
      final params = <String>[
        'SubtitleStreamIndex=$subtitleStreamIndex',
        'SubtitleMethod=HlsEmbed',
      ];
      if (mediaSourceId != null) {
        params.add('MediaSourceId=$mediaSourceId');
      }
      return '$base?${params.join('&')}';
    }
    final base = '$_serverUrl/Videos/$itemId/stream?static=true';
    if (mediaSourceId != null) {
      return '$base&MediaSourceId=$mediaSourceId';
    }
    return base;
  }

  /// 获取单个字幕轨道的直接下载 URL（用于 fvp 原生字幕加载）
  String getSubtitleUrl(
    String itemId, {
    required int subtitleIndex,
    String? mediaSourceId,
    String format = 'srt',
  }) {
    var url =
        '$_serverUrl/Videos/$itemId/Subtitles/$subtitleIndex/Stream.$format';
    if (mediaSourceId != null) {
      url += '?MediaSourceId=$mediaSourceId';
    }
    return url;
  }

  String getImageUrl(String itemId, {String type = 'Primary'}) {
    return '$_serverUrl/Items/$itemId/Images/$type';
  }
}

class LibraryFolder {
  final String id;
  final String name;
  final String collectionType;
  final String posterUrl;

  const LibraryFolder({
    required this.id,
    required this.name,
    required this.collectionType,
    required this.posterUrl,
  });
}
