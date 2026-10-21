import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:himi_syncwatch/models/category_filter.dart';
import 'package:himi_syncwatch/models/emby_playback_settings.dart';
import 'package:himi_syncwatch/models/library_counts.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/media_item.dart';

/// Emby 只读请求的可辨识失败（非 401 的网络/超时/服务端错误）。
///
/// v1.2.19：列表类只读方法（[EmbyService.getItems]/[EmbyService.getLibraries]
/// /[EmbyService.getSeasons]/[EmbyService.getSimilarItems]/[EmbyService.getResumeItems]
/// /[EmbyService.getFavoriteItems]/[EmbyService.searchItems]）此前把失败静默
/// 返回空列表，调用方无法区分「加载失败」与「确实为空」→ 首页/剧集页会呈现
/// 无内容、无提示、无重试的空白。现在失败统一抛本异常，调用方据此展示错误态。
class EmbyException implements Exception {
  const EmbyException(this.message);

  /// 面向用户的中文简短提示。
  final String message;

  @override
  String toString() => message;
}

class EmbyService {
  late Dio _dio;
  String? _serverUrl;
  String? _mediaUrl;
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
  String? get mediaUrl => _mediaUrl ?? _serverUrl;
  String? get accessToken => _accessToken;
  String? get serverId => _serverId;

  /// [serverUrl] API 基地址（激活线路；反代线路时为反代 URL）。
  /// [mediaUrl] 媒体基地址（取流/字幕/图片）：反代线路激活时传主线路
  /// URL（媒体直连省反代带宽），缺省与 [serverUrl] 相同。
  void configure({
    required String serverUrl,
    required String accessToken,
    required String userId,
    required String serverId,
    String? mediaUrl,
    String deviceId = 'himi-001',
  }) {
    _serverUrl = serverUrl;
    _mediaUrl = mediaUrl;
    _accessToken = accessToken;
    _userId = userId;
    _serverId = serverId;
    _deviceId = deviceId;

    _dio.options.baseUrl = serverUrl;
    // v1.2.19：给共享 _dio 加超时——此前无超时，弱网/服务器卡顿时请求可长
    // 时间挂起（表现为首页/详情页一直转圈），且集列表等重请求更易耗尽等待。
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    _dio.options.headers['X-Emby-Token'] = accessToken;
    _dio.options.headers['X-Emby-Authorization'] = _buildAuthHeader();
  }

  /// DioException → 面向用户的 [EmbyException]（401 由调用方单独处理）。
  EmbyException _embyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const EmbyException('请求超时，请检查网络');
      case DioExceptionType.connectionError:
        return const EmbyException('无法连接服务器');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return EmbyException(code != null ? '服务器错误 ($code)' : '服务器错误');
      case DioExceptionType.cancel:
        return const EmbyException('请求已取消');
      default:
        return const EmbyException('网络请求失败');
    }
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

  /// 条目列表查询。筛选四参数全部可选：null/空不注入查询串（向后兼容）。
  /// [genres]/[officialRatings] 为管道符 `|` 分隔、[years] 为逗号分隔
  /// （Emby 约定，多选为「或」语义）。
  Future<List<MediaItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? fields,
    String? sortBy,
    String? sortOrder,
    String? filters,
    String? genres,
    String? years,
    String? officialRatings,
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
          if (filters != null && filters.isNotEmpty) 'Filters': filters,
          if (genres != null && genres.isNotEmpty) 'Genres': genres,
          if (years != null && years.isNotEmpty) 'Years': years,
          if (officialRatings != null && officialRatings.isNotEmpty)
            'OfficialRatings': officialRatings,
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
      throw _embyError(e);
    }
  }

  /// 获取剧集的季列表（`GET /Shows/{seriesId}/Seasons`）。
  ///
  /// 返回的季为 `Type:Season` 的 MediaItem：`childCount` = 该季集数，
  /// `posterUrl` 来自 `ImageTags.Primary`（季海报）。非 401 失败抛
  /// [EmbyException]（v1.2.19）；401 照旧 rethrow。调用方可从已有集按
  /// `parentIndexNumber` 分组兜底。
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
      throw _embyError(e);
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

  /// 资源统计：不含多版本 / 包含多版本 × 电影/剧集/集 六个计数。
  ///
  /// - 不含多版本：`/Items/Counts?UserId=`（与首页卡片同口径）
  /// - 包含多版本：`/Items?IncludeItemTypes=X&Recursive=true&Limit=1`
  ///   （无 UserId，读 TotalRecordCount）
  /// 任何失败返回 null，不抛错。
  Future<LibraryCounts?> getLibraryCounts() async {
    try {
      final withoutVersions = await _countsFromEndpoint();
      final withVersions = await _countsFromItemsQuery(includeVersions: true);
      if (withoutVersions == null && withVersions == null) return null;
      return LibraryCounts(
        withoutVersions: withoutVersions,
        withVersions: withVersions,
      );
    } catch (_) {
      return null;
    }
  }

  /// 回退/含多版本：并发三次 `/Items`（Limit=1）读 TotalRecordCount。
  /// [includeVersions]=true 时不传 UserId（服务器全库口径，含多版本）。
  Future<MediaCounts?> _countsFromItemsQuery({bool includeVersions = false}) async {
    const types = ['Movie', 'Series', 'Episode'];
    final responses = await Future.wait([
      for (final type in types)
        _dio.get('/Items', queryParameters: {
          if (!includeVersions && _userId != null) 'UserId': _userId,
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
          // Emby 该端点需要 UserId 才返回结果（缺失会返回空）
          if (_userId != null) 'UserId': _userId,
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
      throw _embyError(e);
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
      throw _embyError(e);
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
      throw _embyError(e);
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
              'Overview,Genres,MediaStreams,MediaSources,AlternateMediaSources,CommunityRating,OfficialRating,ProductionYear,RunTimeTicks,Chapters,ImageTags,UserData,ProviderIds,ExternalUrls,Studios,Path,DateCreated',
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

  /// 移出「继续观看」。
  ///
  /// Emby 官方端点 `POST /Users/{UserId}/Items/{Id}/HideFromResume?Hide=true`
  /// —— 剧集在 `/Items/Resume` 中返回的是「当前未看完集」或「下一未观看集」
  /// （NextUp 条目，可能本身没有进度），单纯清进度对后者是空操作，故此前剧集
  /// 移除后重启会复现。该端点对两种条目都生效，且再次播放时服务器会自动
  /// 重新武装（re-arm）。同时尽力清空已有进度以保持电影等旧行为。
  /// 以 `HideFromResume` 是否成功作为返回值。
  Future<bool> removeFromResume(String itemId) async {
    var ok = false;
    try {
      await _dio.post(
        '/Users/$_userId/Items/$itemId/HideFromResume',
        queryParameters: {'Hide': true},
      );
      ok = true;
    } on DioException {
      ok = false;
    }
    try {
      await _dio.post(
        '/Users/$_userId/Items/$itemId/UserData',
        data: <String, dynamic>{'PlaybackPositionTicks': 0},
      );
    } on DioException {
      // 忽略：HideFromResume 已达成移出目的。
    }
    return ok;
  }

  /// 各媒体库的播放阈值（按库）：`GET /Library/VirtualFolders/Query`
  /// → 每项 `ItemId`（库根条目 id）+ `LibraryOptions`（含阈值字段）。
  /// 任何失败返回空 Map（调用方回退全局设置）。
  Future<Map<String, EmbyPlaybackSettings>> getLibraryPlaybackSettings() async {
    try {
      final resp = await _dio.get(
        '/Library/VirtualFolders/Query',
        queryParameters: {if (_userId != null) 'UserId': _userId},
      );
      final data = resp.data;
      if (data is! List) return const {};
      final map = <String, EmbyPlaybackSettings>{};
      for (final f in data) {
        if (f is! Map) continue;
        final id = f['ItemId'];
        final options = f['LibraryOptions'];
        if (id is! String || id.isEmpty || options is! Map) continue;
        map[id] = EmbyPlaybackSettings.fromJson(options.cast<String, dynamic>());
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  /// 服务器全局播放阈值：`GET /System/Configuration` → ServerConfiguration。
  /// 失败返回 [EmbyPlaybackSettings.fallback]。
  Future<EmbyPlaybackSettings> getGlobalPlaybackSettings() async {
    try {
      final resp = await _dio.get('/System/Configuration');
      final data = resp.data;
      if (data is! Map) return EmbyPlaybackSettings.fallback;
      return EmbyPlaybackSettings.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return EmbyPlaybackSettings.fallback;
    }
  }

  /// 条目祖先链 id（由近及远，不含条目自身）：`GET /Items/{Id}/Ancestors`。
  /// 用于把条目映射到所属媒体库（祖先中命中库根 `ItemId` 者）。失败返回空。
  Future<List<String>> getAncestorIds(String itemId) async {
    try {
      final resp = await _dio.get(
        '/Items/$itemId/Ancestors',
        queryParameters: {if (_userId != null) 'UserId': _userId},
      );
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => e['Id'])
          .whereType<String>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 当前服务器全部收藏条目（电影/剧集/单集），供收藏页分组展示。
  /// `Filters=IsFavorite` 服务端过滤；字段含 `UserData` 以便回显收藏态。
  /// 筛选参数与 [getItems] 同约定；[filters] 会与 `IsFavorite` 合并。
  /// 非 401 失败抛 [EmbyException]（v1.2.19）。
  Future<List<MediaItem>> getFavoriteItems({
    String? includeItemTypes,
    String? sortBy,
    String? sortOrder,
    String? filters,
    String? genres,
    String? years,
    String? officialRatings,
  }) async {
    try {
      final filterValue = (filters == null || filters.isEmpty)
          ? 'IsFavorite'
          : 'IsFavorite,$filters';
      final response = await _dio.get(
        '/Items',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          'Recursive': true,
          'IncludeItemTypes': includeItemTypes ?? 'Movie,Series,Episode',
          'Filters': filterValue,
          if (genres != null && genres.isNotEmpty) 'Genres': genres,
          if (years != null && years.isNotEmpty) 'Years': years,
          if (officialRatings != null && officialRatings.isNotEmpty)
            'OfficialRatings': officialRatings,
          'Fields':
              'UserData,ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,Overview,PremiereDate',
          'ImageTypeLimit': 1,
          'SortBy': sortBy ?? 'SortName',
          'SortOrder': sortOrder ?? 'Ascending',
        },
      );
      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      throw _embyError(e);
    }
  }

  /// 筛选面板可选项。并行请求聚合端点 `GET /Items/Filters` 与三个
  /// 专用端点 `/Genres`、`/Years`、`/OfficialRatings`（Emby 各版本
  /// 兼容性最好），任一路成功即贡献数据，合并去重（年份降序、名称
  /// 字母序）；全部失败返回空对象（面板降级隐藏对应分组），不抛错。
  /// [parentId] 为 null 时为全服务器（收藏页）；[includeItemTypes]
  /// 限定电影或剧集。
  Future<MediaFilterOptions> getFilterOptions({
    String? parentId,
    String? includeItemTypes,
  }) async {
    final query = <String, dynamic>{
      if (_userId != null) 'UserId': _userId,
      if (parentId != null) 'ParentId': parentId,
      if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
    };

    final results = await Future.wait<dynamic>([
      _safeFilterJson('/Items/Filters', query),
      _safeFilterJson('/Genres', query),
      _safeFilterJson('/Years', query),
      _safeFilterJson('/OfficialRatings', query),
    ]);

    final filters = results[0];
    final genreSet = <String>{
      if (filters is Map) ..._parseNameList(filters['Genres']),
      ..._namesFromItems(results[1]),
    };
    final yearSet = <int>{
      if (filters is Map) ..._parseIntList(filters['Years']),
      ..._yearsFromItems(results[2]),
    };
    final ratingSet = <String>{
      if (filters is Map) ..._parseNameList(filters['OfficialRatings']),
      ..._namesFromItems(results[3]),
    };

    var years = yearSet.toList()..sort((a, b) => b.compareTo(a));
    var ratings = ratingSet.toList()..sort();

    // 兜底：Emby 4.9.x 既无 `/Items/Filters`（Jellyfin 端点，404），
    // `/OfficialRatings` 也常不可用；年份/分级任一为空时，直接扫描条目
    // 聚合 `ProductionYear` / `OfficialRating`，保证面板可选维度可用。
    if (years.isEmpty || ratings.isEmpty) {
      final scan = await _scanFacets(
        parentId: parentId,
        includeItemTypes: includeItemTypes,
      );
      if (years.isEmpty && scan.years.isNotEmpty) {
        yearSet.addAll(scan.years);
        years = yearSet.toList()..sort((a, b) => b.compareTo(a));
      }
      if (ratings.isEmpty && scan.ratings.isNotEmpty) {
        ratingSet.addAll(scan.ratings);
        ratings = ratingSet.toList()..sort();
      }
    }

    final genres = genreSet.toList()..sort();
    return MediaFilterOptions(genres: genres, years: years, ratings: ratings);
  }

  /// 有界扫描条目聚合年份/官方分级（专用端点缺失时的兜底）。
  /// 逐页 `GET /Items`（`Fields=ProductionYear,OfficialRating`），
  /// 最多 [_scanMaxPages] 页或提前在短页停止；失败返回空，不抛错。
  static const int _scanPageSize = 500;
  static const int _scanMaxPages = 6;

  Future<({List<int> years, List<String> ratings})> _scanFacets({
    String? parentId,
    String? includeItemTypes,
  }) async {
    final years = <int>{};
    final ratings = <String>{};
    try {
      for (var page = 0; page < _scanMaxPages; page++) {
        final response = await _dio.get(
          '/Items',
          queryParameters: {
            if (_userId != null) 'UserId': _userId,
            if (parentId != null) 'ParentId': parentId,
            if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
            'Recursive': true,
            'Fields': 'ProductionYear,OfficialRating',
            'EnableTotalRecordCount': false,
            'Limit': _scanPageSize,
            'StartIndex': page * _scanPageSize,
          },
        );
        final data = response.data;
        final items = (data is Map ? data['Items'] : null) as List<dynamic>? ??
            const [];
        for (final raw in items) {
          if (raw is! Map) continue;
          final year = raw['ProductionYear'];
          if (year is int) {
            years.add(year);
          } else if (year is num) {
            years.add(year.toInt());
          } else if (year is String) {
            final parsed = int.tryParse(year);
            if (parsed != null) years.add(parsed);
          }
          final rating = raw['OfficialRating'];
          if (rating is String && rating.isNotEmpty) ratings.add(rating);
        }
        if (items.length < _scanPageSize) break;
      }
    } catch (e) {
      debugPrint('EmbyService.getFilterOptions(_scanFacets) failed: $e');
    }
    return (years: years.toList(), ratings: ratings.toList());
  }

  /// 单路筛选请求：失败（404/网络/解析）打日志并返回 null，不中断其余路。
  Future<dynamic> _safeFilterJson(
    String path,
    Map<String, dynamic> query,
  ) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      return response.data;
    } on DioException catch (e) {
      debugPrint(
        'EmbyService.getFilterOptions($path) failed: '
        'status=${e.response?.statusCode} ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('EmbyService.getFilterOptions($path) failed: $e');
      return null;
    }
  }

  /// 专用端点响应 → 名称列表：裸数组或 `{Items:[...]}`（ItemsResult）。
  List<String> _namesFromItems(dynamic data) {
    if (data is List) return _parseNameList(data);
    if (data is Map && data['Items'] is List) {
      return _parseNameList(data['Items']);
    }
    return const [];
  }

  /// 专用端点响应 → 年份列表：裸数组或 `{Items:[...]}`。
  List<int> _yearsFromItems(dynamic data) {
    if (data is List) return _parseIntList(data);
    if (data is Map && data['Items'] is List) {
      return _parseIntList(data['Items']);
    }
    return const [];
  }

  /// `NameIdPair` 列表（或纯字符串列表）→ 名称列表；无法解析的项忽略。
  List<String> _parseNameList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) {
          if (e is String) return e;
          if (e is Map && e['Name'] is String) return e['Name'] as String;
          return null;
        })
        .whereType<String>()
        .toList();
  }

  /// 年份列表（int/num/字符串/NameIdPair 混容）→ int 列表；无法解析的忽略。
  List<int> _parseIntList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) {
          if (e is int) return e;
          if (e is num) return e.toInt();
          if (e is String) return int.tryParse(e);
          if (e is Map) {
            // Emby/Jellyfin 年份项形如 {Name:"2024", Id:非数字}：Name 才是年份，
            // Id 往往是 GUID/非数字，优先解析 Name，失败再回退 Id。
            final name = e['Name'];
            if (name is int) return name;
            if (name is num) return name.toInt();
            if (name is String) {
              final parsed = int.tryParse(name);
              if (parsed != null) return parsed;
            }
            final id = e['Id'];
            if (id is int) return id;
            if (id is num) return id.toInt();
            if (id is String) return int.tryParse(id);
          }
          return null;
        })
        .whereType<int>()
        .toList();
  }

  /// 当前服务器「继续观看」条目（有播放进度的电影/剧集/单集）。
  /// `GET /Users/{userId}/Items/Resume`；字段含 `UserData`（进度/百分比）。
  /// 非 401 失败抛 [EmbyException]（v1.2.19）。
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
      throw _embyError(e);
    }
  }

  /// 取官方 `PlaySessionId`（`POST /Items/{id}/PlaybackInfo`）。Emby 需要用它
  /// 关联播放会话，`Sessions/Playing*` 上报才能把进度写入 `UserData`（Resume）。
  /// 失败返回 null（调用方回退本地生成 id）。
  Future<String?> getPlaySessionId({
    required String itemId,
    String? mediaSourceId,
  }) async {
    return (await getPlaybackInfo(itemId: itemId, mediaSourceId: mediaSourceId))
        .playSessionId;
  }

  /// `POST /Items/{id}/PlaybackInfo` 完整解析：`PlaySessionId` + `MediaSources`
  /// （供 STRM 直链播放解析服务器返回的直链地址）。失败返回空结果。
  Future<EmbyPlaybackInfo> getPlaybackInfo({
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
      final data = response.data as Map?;
      final id = data?['PlaySessionId'];
      final sources = (data?['MediaSources'] as List?)
              ?.whereType<Map>()
              .map((m) => MediaSource.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const <MediaSource>[];
      return EmbyPlaybackInfo(
        playSessionId: id is String && id.isNotEmpty ? id : null,
        sources: sources,
      );
    } on DioException {
      return const EmbyPlaybackInfo();
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
    final base = '${mediaUrl ?? _serverUrl}';
    if (subtitleStreamIndex != null) {
      final streamBase = '$base/Videos/$itemId/stream';
      final params = <String>[
        'SubtitleStreamIndex=$subtitleStreamIndex',
        'SubtitleMethod=HlsEmbed',
      ];
      if (mediaSourceId != null) {
        params.add('MediaSourceId=$mediaSourceId');
      }
      return '$streamBase?${params.join('&')}';
    }
    final streamBase = '$base/Videos/$itemId/stream?static=true';
    if (mediaSourceId != null) {
      return '$streamBase&MediaSourceId=$mediaSourceId';
    }
    return streamBase;
  }

  /// 获取单个字幕轨道的直接下载 URL（用于 fvp 原生字幕加载）
  String getSubtitleUrl(
    String itemId, {
    required int subtitleIndex,
    String? mediaSourceId,
    String format = 'srt',
  }) {
    var url =
        '${mediaUrl ?? _serverUrl}/Videos/$itemId/Subtitles/$subtitleIndex/Stream.$format';
    if (mediaSourceId != null) {
      url += '?MediaSourceId=$mediaSourceId';
    }
    return url;
  }

  /// 下载字幕文本（字幕延迟：解析偏移后写临时文件外挂）。
  /// 服务端统一转出 SRT；ResponseType.plain 防非 JSON 内容解析失败。
  Future<String> fetchSubtitleText(
    String itemId, {
    required int subtitleIndex,
    String? mediaSourceId,
    String format = 'srt',
  }) async {
    final url = getSubtitleUrl(
      itemId,
      subtitleIndex: subtitleIndex,
      mediaSourceId: mediaSourceId,
      format: format,
    );
    final resp = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return resp.data ?? '';
  }

  String getImageUrl(String itemId, {String type = 'Primary'}) {
    return '${mediaUrl ?? _serverUrl}/Items/$itemId/Images/$type';
  }

  /// 当前用户头像 URL（`GET /Users/{userId}/Images/Primary`）。
  /// [tag] 非空时附加为查询参数用于刷新缓存（上传头像后破缓存）。
  String getUserImageUrl({String? tag}) {
    final base = '${mediaUrl ?? _serverUrl}/Users/$_userId/Images/Primary';
    return (tag != null && tag.isNotEmpty) ? '$base?tag=$tag' : base;
  }

  /// 修改当前用户密码（`POST /Users/{userId}/Password`）。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post(
      '/Users/$_userId/Password',
      data: {'CurrentPw': currentPassword, 'NewPw': newPassword},
    );
  }

  /// 上传当前用户头像（`POST /Users/{userId}/Images/Primary`）。
  ///
  /// Emby 该接口要求 body 为 **base64 编码**的图片字符串（官方文档
  /// "must be base64 encoded"）；直接发原始字节会被当作 base64 解码成
  /// 无效图片，表现为「上传成功但头像不变」。
  Future<void> uploadUserImage(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    await _dio.post(
      '/Users/$_userId/Images/Primary',
      data: base64Encode(bytes),
      options: Options(
        headers: {Headers.contentTypeHeader: contentType},
      ),
    );
  }

  /// 读取当前用户头像的 Emby 图片 tag（`PrimaryImageTag`）；无头像返回 null。
  Future<String?> getUserImageTag() async {
    final response = await _dio.get('/Users/$_userId');
    final data = response.data as Map<String, dynamic>?;
    final tag = data?['PrimaryImageTag'] as String?;
    return (tag != null && tag.isNotEmpty) ? tag : null;
  }
}

/// `POST /Items/{id}/PlaybackInfo` 解析结果。
class EmbyPlaybackInfo {
  const EmbyPlaybackInfo({this.playSessionId, this.sources = const []});

  final String? playSessionId;
  final List<MediaSource> sources;

  /// 按媒体源 id 取源；[id] 为空或未命中时回退首个源。
  MediaSource? sourceById(String? id) {
    if (id != null && id.isNotEmpty) {
      for (final s in sources) {
        if (s.id == id) return s;
      }
    }
    return sources.isNotEmpty ? sources.first : null;
  }
}

/// 是否绝对 http(s) URL（STRM 直链判定）。
bool isAbsoluteHttpUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// STRM 直链播放地址解析：优先服务器返回的绝对直链
/// （`DirectStreamUrl`），其次 `.strm` 内容 URL（`Path`），均不可用时回退
/// 代理取流地址 [proxyUrl]（服务器不兼容或返回相对地址时）。
String resolveStrmDirectUrl({
  required MediaSource? source,
  required String proxyUrl,
}) {
  final direct = source?.directStreamUrl;
  if (isAbsoluteHttpUrl(direct)) return direct!;
  final path = source?.path;
  if (isAbsoluteHttpUrl(path)) return path!;
  return proxyUrl;
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
