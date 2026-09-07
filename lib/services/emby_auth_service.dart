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
    return 'Emby Client="HimiSync", Device="Desktop", '
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
    required String accessToken,
  }) async {
    final data = {
      'serverId': serverId,
      'serverUrl': serverUrl,
      'serverName': serverName,
      'userId': userId,
      'username': username,
      'accessToken': accessToken,
    };
    await _secureStorage.write(key: 'session_$serverId', value: jsonEncode(data));
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
