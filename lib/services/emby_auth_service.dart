import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';

class EmbyAuthService {
  final FlutterSecureStorage _secureStorage;
  String? _deviceId;

  EmbyAuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String get deviceId => _deviceId ?? 'unknown';

  Future<void> init() async {
    _deviceId = await _getDeviceId();
  }

  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return android.id;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return ios.identifierForVendor ?? 'ios-unknown';
      } else if (Platform.isLinux) {
        final linux = await deviceInfo.linuxInfo;
        return linux.machineId ?? 'linux-unknown';
      } else if (Platform.isMacOS) {
        final mac = await deviceInfo.macOsInfo;
        return mac.systemGUID ?? 'macos-unknown';
      } else if (Platform.isWindows) {
        final windows = await deviceInfo.windowsInfo;
        return windows.deviceId;
      }
    } catch (_) {}
    return 'himi-${DateTime.now().millisecondsSinceEpoch}';
  }

  String _authHeader(String serverId, String userId, String token) {
    return 'Emby Client="HIMI", Device="Desktop", '
        'DeviceId="$deviceId", Version="1.0.0", '
        'UserId="$userId", Token="$token", ServerId="$serverId"';
  }

  Future<Map<String, dynamic>?> loadSession(String serverId) async {
    final json = await _secureStorage.read(key: 'session_$serverId');
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<void> saveSession({
    required String serverId,
    required String serverUrl,
    required String serverName,
    required String userId,
    required String username,
    required String id,          // 新增：本地 UUID，用于服务器去重
    required String accessToken,
    List<Map<String, dynamic>> routes = const [],
    String? activeRouteUrl,
    bool autoFailover = true,
    bool strmDirectPlay = false,
  }) async {
    final data = {
      'id': id,                // 新增：保存 id 字段，防止重启后全勾选
      'serverId': serverId,
      'serverUrl': serverUrl,
      'serverName': serverName,
      'userId': userId,
      'username': username,
      'accessToken': accessToken,
      if (routes.isNotEmpty) 'routes': routes,
      if (activeRouteUrl != null) 'activeRouteUrl': activeRouteUrl,
      'autoFailover': autoFailover,
      'strmDirectPlay': strmDirectPlay,
    };
    await _secureStorage.write(key: 'session_$serverId', value: jsonEncode(data));
  }

  /// 线路字段更新落盘（读-改-写，保留其余会话字段）。
  Future<void> updateSessionRoutes({
    required String serverId,
    required List<Map<String, dynamic>> routes,
    String? activeRouteUrl,
    required bool autoFailover,
    bool? strmDirectPlay,
  }) async {
    final session = await loadSession(serverId);
    if (session == null) return;
    session['routes'] = routes;
    if (activeRouteUrl != null) {
      session['activeRouteUrl'] = activeRouteUrl;
    } else {
      session.remove('activeRouteUrl');
    }
    session['autoFailover'] = autoFailover;
    if (strmDirectPlay != null) session['strmDirectPlay'] = strmDirectPlay;
    await _secureStorage.write(key: 'session_$serverId', value: jsonEncode(session));
  }

  Future<void> deleteSession(String serverId) async {
    await _secureStorage.delete(key: 'session_$serverId');
  }

  Future<List<String>> listServerIds() async {
    final all = await _secureStorage.readAll();
    return all.keys
        .where((k) => k.startsWith('session_'))
        .map((k) => k.substring(8))
        .toList();
  }

  Future<void> deleteAllSessions() async {
    final all = await _secureStorage.readAll();
    for (final key in all.keys) {
      if (key.startsWith('session_')) {
        await _secureStorage.delete(key: key);
      }
    }
  }

  Future<void> saveSelectedServerId(String configId) async {
    await _secureStorage.write(key: 'selected_config_id', value: configId);
  }

  Future<String?> loadSelectedServerId() async {
    return await _secureStorage.read(key: 'selected_config_id');
  }

  /// 服务器列表的用户自定义顺序（config.id 有序列表）。
  ///
  /// `listServerIds()` 的顺序来自 readAll，各平台无保证；拖拽排序后把顺序
  /// 落盘到这里，首页加载时据此稳定排序（不在序里的排尾部 = 新加的靠后）。
  Future<void> saveServerOrder(List<String> configIds) async {
    await _secureStorage.write(key: 'server_order', value: jsonEncode(configIds));
  }

  Future<List<String>> loadServerOrder() async {
    final raw = await _secureStorage.read(key: 'server_order');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<Dio> createDio({
    required String serverUrl,
    required String accessToken,
    required String serverId,
    required String userId,
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: serverUrl,
      headers: {
        'X-Emby-Token': accessToken,
        'X-Emby-Authorization': _authHeader(serverId, userId, accessToken),
      },
    ));

    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      return client;
    };

    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          handler.reject(DioException(
            requestOptions: error.requestOptions,
            error: EmbyTokenExpiredException(serverId),
            type: error.type,
          ));
          return;
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  Future<Dio> pingServer(String serverUrl) async {
    final dio = Dio(BaseOptions(baseUrl: serverUrl, connectTimeout: const Duration(seconds: 5)));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      return client;
    };
    return dio;
  }
}

class EmbyTokenExpiredException implements Exception {
  final String serverId;
  EmbyTokenExpiredException(this.serverId);
  @override
  String toString() => 'Token expired for server $serverId';
}
