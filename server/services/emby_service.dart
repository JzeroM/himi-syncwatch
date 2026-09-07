import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/env_config.dart';

class EmbyService {
  final EnvConfig _config;
  late final Dio _dio;

  EmbyService(this._config) {
    _dio = Dio();
    _dio.options.baseUrl = _config.embyServerUrl;
    _dio.options.headers['X-Emby-Authorization'] =
        'MediaBrowser Client="HimiSync-Backend", Device="Server", DeviceId="himi-sync-server-001", Version="1.0.0"';
  }

  /// 代理 Emby 认证
  Future<Map<String, dynamic>?> authenticate({
    required String username,
    required String password,
    String? serverUrl,
  }) async {
    try {
      final baseUrl = serverUrl ?? _config.embyServerUrl;
      final response = await Dio().post(
        '$baseUrl/Users/authenticatebyname',
        data: {'Username': username, 'Pw': password},
        options: Options(
          headers: {
            'X-Emby-Authorization':
                'MediaBrowser Client="HimiSync-Backend", Device="Server", DeviceId="himi-sync-server-001", Version="1.0.0"',
          },
        ),
      );

      return {
        'accessToken': response.data['AccessToken'],
        'userId': response.data['User']['Id'],
        'serverUrl': baseUrl,
      };
    } catch (e) {
      print('Emby 认证失败: $e');
      return null;
    }
  }

  /// 获取媒体列表
  Future<List<Map<String, dynamic>>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? accessToken,
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
        options: accessToken != null
            ? Options(headers: {'X-Emby-Token': accessToken})
            : null,
      );

      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } catch (e) {
      print('获取媒体列表失败: $e');
      return [];
    }
  }

  /// 搜索媒体
  Future<List<Map<String, dynamic>>> search({
    required String query,
    String? accessToken,
  }) async {
    try {
      final response = await _dio.get(
        '/Search/Hints',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Movie,Series,Episode',
          'Limit': 20,
        },
        options: accessToken != null
            ? Options(headers: {'X-Emby-Token': accessToken})
            : null,
      );

      final items = response.data['SearchHints'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } catch (e) {
      print('搜索失败: $e');
      return [];
    }
  }

  /// 获取媒体详情
  Future<Map<String, dynamic>?> getItemDetails({
    required String id,
    String? accessToken,
  }) async {
    try {
      final response = await _dio.get(
        '/Items/$id',
        options: accessToken != null
            ? Options(headers: {'X-Emby-Token': accessToken})
            : null,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('获取详情失败: $e');
      return null;
    }
  }
}
