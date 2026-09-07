import 'package:dio/dio.dart';
import 'package:himi_syncwatch/models/media_item.dart';

class EmbyService {
  late final Dio _dio;
  String? _serverUrl;
  String? _accessToken;

  EmbyService() {
    _dio = Dio();
  }

  String? get serverUrl => _serverUrl;
  String? get accessToken => _accessToken;

  void configure({required String serverUrl, required String accessToken}) {
    _serverUrl = serverUrl;
    _accessToken = accessToken;
    _dio.options.baseUrl = serverUrl;
    _dio.options.headers['X-Emby-Authorization'] =
        'MediaBrowser Client="HimiSync", Device="Desktop", DeviceId="himi-sync-001", Version="1.0.0"';
    _dio.options.headers['X-Emby-Token'] = accessToken;
  }

  Future<String?> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      _serverUrl = serverUrl;
      _dio.options.baseUrl = serverUrl;
      _dio.options.headers['X-Emby-Authorization'] =
          'MediaBrowser Client="HimiSync", Device="Desktop", DeviceId="himi-sync-001", Version="1.0.0"';

      final response = await _dio.post(
        '/Users/authenticatebyname',
        data: {'Username': username, 'Pw': password},
      );

      final token = response.data['AccessToken'];
      final userId = response.data['User']['Id'];

      if (token != null) {
        _accessToken = token;
        _dio.options.headers['X-Emby-Token'] = token;
        return userId;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<MediaItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
  }) async {
    try {
      final response = await _dio.get(
        '/Users/me/Items',
        queryParameters: {
          if (parentId != null) 'ParentId': parentId,
          if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
          if (limit != null) 'Limit': limit,
          if (startIndex != null) 'StartIndex': startIndex,
          'Recursive': true,
          'Fields': 'Overview,Genres,MediaStreams',
          'ImageTypeLimit': 1,
        },
      );

      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaItem>> searchItems(String query) async {
    try {
      final response = await _dio.get(
        '/Search/Hints',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Movie,Series,Episode',
          'Limit': 20,
        },
      );

      final items = response.data['SearchHints'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<MediaItem?> getItemDetails(String id) async {
    try {
      final response = await _dio.get('/Items/$id');
      return MediaItem.fromJson(response.data, serverUrl: _serverUrl);
    } catch (e) {
      return null;
    }
  }

  String getStreamUrl(String itemId) {
    return '$_serverUrl/Videos/$itemId/stream?static=true';
  }

  String getImageUrl(String itemId, {String type = 'Primary'}) {
    return '$_serverUrl/Items/$itemId/Images/$type';
  }
}
