import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:himi_syncwatch/models/media_item.dart';

class EmbyService {
  late final Dio _dio;
  String? _serverUrl;
  String? _accessToken;
  String? _userId;

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

  void configure(
      {required String serverUrl,
      required String accessToken,
      String? userId}) {
    _serverUrl = serverUrl;
    _accessToken = accessToken;
    _userId = userId;
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
    String? fields,
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
          'Recursive': true,
          'Fields': fields ?? 'Overview,Genres,MediaStreams',
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

  static const _posterWallFields =
      'ImageTags,PrimaryImageAspectRatio,ProductionYear,ChildCount,CommunityRating';

  Future<List<MediaItem>> getAllItems({
    String? includeItemTypes,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/Items',
        queryParameters: {
          if (_userId != null) 'UserId': _userId,
          if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
          'Limit': limit,
          'Recursive': true,
          'Fields': _posterWallFields,
          'ImageTypeLimit': 1,
          'OrderBy': 'DateCreated DESC',
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
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaItem>> getSimilarItems(String itemId, {int limit = 10}) async {
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
          'IncludeItemTypes': 'Movie,Series',
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

  Future<List<LibraryFolder>> getLibraries() async {
    try {
      final response = await _dio.get('/Library/VirtualFolders');
      final folders = <LibraryFolder>[];
      for (final f in response.data) {
        final name = f['Name'] as String? ?? '';
        final itemId = (f['ItemId'] ?? f['Id'])?.toString() ?? '';
        final collectionType = f['CollectionType'] as String? ?? '';
        if (name.isNotEmpty && itemId.isNotEmpty) {
          final posterUrl = '$_serverUrl/Items/$itemId/Images/Primary?maxHeight=300';
          folders.add(LibraryFolder(
            id: itemId,
            name: name,
            collectionType: collectionType,
            posterUrl: posterUrl,
          ));
        }
      }
      return folders;
    } catch (e) {
      return [];
    }
  }

  Future<MediaItem?> getItemDetails(String id) async {
    try {
      final response = await _dio.get(
        '/Users/$_userId/Items/$id',
        queryParameters: {
          'Fields': 'Overview,Genres,MediaStreams,CommunityRating,OfficialRating,ProductionYear,RunTimeTicks',
        },
      );
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
