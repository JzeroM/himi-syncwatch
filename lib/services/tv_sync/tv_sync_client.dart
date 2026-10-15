import 'package:dio/dio.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';

/// TV 同步客户端（手机 → TV TvSyncServer）。
class TvSyncClient {
  TvSyncClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 查询 TV 身份（免鉴权，验证连通性用）。
  Future<({String deviceId, String name})> info(String baseUrl) async {
    final resp = await _dio.get(
      '$baseUrl/api/info',
      options: Options(sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5)),
    );
    final data = resp.data;
    if (data is! Map<String, dynamic> || data['ok'] != true) {
      throw TvSyncException('TV 响应异常');
    }
    return (
      deviceId: data['deviceId'] as String? ?? '',
      name: data['name'] as String? ?? 'HIMI TV',
    );
  }

  /// 发起配对（TV 弹确认框）。同意返回 token；拒绝/失败抛
  /// [TvSyncException]（message 为 TV 端 error 文案）。
  Future<String> pair(String baseUrl, {required String phoneName}) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/api/pair',
        data: {'phoneName': phoneName},
        options: Options(sendTimeout: const Duration(seconds: 65),
            receiveTimeout: const Duration(seconds: 65)),
      );
      final data = resp.data;
      if (data is Map<String, dynamic> && data['ok'] == true) {
        final token = data['token'] as String?;
        if (token == null || token.isEmpty) {
          throw TvSyncException('TV 未返回配对令牌');
        }
        return token;
      }
      throw TvSyncException(_errorMessage(data));
    } on DioException catch (e) {
      throw TvSyncException(_errorMessage(e.response?.data, fallback: '配对失败：${e.message}'));
    }
  }

  /// 推送服务器配置（单个=长度1，全部=N）。token 失效抛
  /// [TvSyncException]（message 含「配对已失效」）。
  Future<void> pushServers(
    String baseUrl, {
    required String token,
    required List<EmbyServerConfig> servers,
  }) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/api/sync',
        data: {'servers': servers.map((s) => s.toJson()).toList()},
        options: Options(
          headers: {'X-Himi-Token': token},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = resp.data;
      if (data is Map<String, dynamic> && data['ok'] == true) return;
      throw TvSyncException(_errorMessage(data));
    } on DioException catch (e) {
      throw TvSyncException(
          _errorMessage(e.response?.data, fallback: '同步失败：${e.message}'));
    }
  }

  String _errorMessage(dynamic data, {String fallback = '请求失败'}) {
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is String && err.isNotEmpty) return err;
    }
    return fallback;
  }
}

class TvSyncException implements Exception {
  TvSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
