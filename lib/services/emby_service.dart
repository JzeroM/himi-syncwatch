import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
    return 'Emby Client="HimiSync", Device="Desktop", '
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
        'Emby Client="HimiSync", Device="Desktop", '
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
          'Fields': fields ?? 'ImageTags,PrimaryImageAspectRatio,ProductionYear,Overview,Genres,MediaStreams',
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
          'Fields': 'CommunityRating,ProductionYear,ImageTags',
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
        '/Search/Hints',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Movie,Series',
          'Limit': 20,
        },
      );

      final items = response.data['SearchHints'] as List<dynamic>? ?? [];
      return items
          .map((item) => MediaItem.fromJson(item, serverUrl: _serverUrl))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return [];
    }
  }

  Future<List<LibraryFolder>> getLibraries() async {
    try {
      final response = await _dio.get('/Library/VirtualFolders');
      final folders = <LibraryFolder>[];
      for (final f in response.data) {
        final name = f['Name'] as String? ?? '';
        final itemId = (f['ItemId'] ?? f['Id'])?.toString() ?? '';
        final collectionType = f['CollectionType'] as String? ?? '';
        if (name.isNotEmpty && itemId.isNotEmpty) {
          final posterUrl =
              '$_serverUrl/Items/$itemId/Images/Primary?maxHeight=300';
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
          'Fields':
              'Overview,Genres,MediaStreams,CommunityRating,OfficialRating,ProductionYear,RunTimeTicks',
        },
      );
      return MediaItem.fromJson(response.data, serverUrl: _serverUrl);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) rethrow;
      return null;
    }
  }

  String getStreamUrl(String itemId) {
    return '$_serverUrl/Videos/$itemId/master.m3u8?Static=true&api_key=$_accessToken';
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
