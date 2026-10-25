import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

class TraktAuthException implements Exception {
  final String code;
  final String message;

  const TraktAuthException(this.code, this.message);

  @override
  String toString() => 'TraktAuthException($code): $message';
}

class TraktAuthService {
  static const pkceMaxAge = Duration(minutes: 10);

  final TraktConfig config;
  final TraktTokenStore store;
  final Dio _dio;
  final DateTime Function() _now;
  final Random _random;

  Future<TraktTokens>? _refreshFuture;

  TraktAuthService({
    this.config = const TraktConfig(),
    TraktTokenStore? store,
    Dio? dio,
    DateTime Function()? now,
    Random? random,
  })  : store = store ?? TraktTokenStore(),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (_) => true,
            )),
        _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  Map<String, String> get _publicHeaders => {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': config.clientId,
        'User-Agent': config.userAgent,
      };

  Map<String, String> headersFor(TraktTokens tokens) => {
        ..._publicHeaders,
        'Authorization': '${tokens.tokenType} ${tokens.accessToken}',
      };

  static String _normalizePath(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static String challengeForVerifier(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomUrlSafe(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<Uri> beginPkce() async {
    if (!config.isConfigured) {
      throw const TraktAuthException(
        'missing_client_id',
        '未注入 Trakt Client ID',
      );
    }
    final verifier = _randomUrlSafe(48);
    final state = _randomUrlSafe(24);
    await store.writePkce(
      TraktPkceSession(
        verifier: verifier,
        state: state,
        createdAt: _now(),
      ),
    );
    return config.buildAuthorizeUri(
      state: state,
      codeChallenge: challengeForVerifier(verifier),
    );
  }

  Future<TraktTokens> handleCallback(Uri uri) async {
    if (uri.scheme != TraktConfig.callbackScheme ||
        uri.host != TraktConfig.callbackHost ||
        _normalizePath(uri.path) != TraktConfig.callbackPath) {
      throw const TraktAuthException('invalid_callback', '无效的授权回调');
    }
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      await store.clearPkce();
      final description = uri.queryParameters['error_description'];
      throw TraktAuthException(
        error,
        description == null || description.isEmpty ? '授权已取消' : description,
      );
    }
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      throw const TraktAuthException('missing_code', '授权回调缺少 code 或 state');
    }
    final session = await store.readPkce();
    await store.clearPkce();
    if (session == null) {
      throw const TraktAuthException('missing_session', '授权会话不存在或已使用');
    }
    if (session.isExpired(now: _now(), maxAge: pkceMaxAge)) {
      throw const TraktAuthException('expired_session', '授权会话已过期');
    }
    if (session.state != state) {
      throw const TraktAuthException('state_mismatch', '授权状态校验失败');
    }
    return _exchangeCode(code: code, verifier: session.verifier);
  }

  Future<TraktTokens> _exchangeCode({
    required String code,
    required String verifier,
  }) async {
    final tokens = await _postToken(
      {
        'code': code,
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
      fallbackMessage: '授权码兑换失败',
    );
    await store.writeTokens(tokens);
    return tokens;
  }

  Future<TraktDeviceCode> startDeviceFlow() async {
    if (!config.isConfigured) {
      throw const TraktAuthException(
        'missing_client_id',
        '未注入 Trakt Client ID',
      );
    }
    final response = await _post(
      config.deviceCodeUrl,
      {'client_id': config.clientId},
    );
    final data = _mapBody(response);
    if (response.statusCode == 200) {
      final code = TraktDeviceCode.fromJson(data);
      if (code.deviceCode.isEmpty || code.userCode.isEmpty) {
        throw const TraktAuthException('invalid_device_code', '设备码响应不完整');
      }
      await store.writeDeviceCode(code);
      return code;
    }
    throw TraktAuthException(
      'device_code_failed',
      _errorMessage(data) ?? '获取设备码失败',
    );
  }

  Future<TraktDevicePollResult> pollDeviceFlow(TraktDeviceCode code) async {
    final response = await _post(
      config.deviceTokenUrl,
      {'code': code.deviceCode, 'client_id': config.clientId},
    );
    final data = _mapBody(response);
    switch (response.statusCode) {
      case 200:
        final tokens = TraktTokens.fromResponse(data, now: _now());
        if (tokens.accessToken.isEmpty) {
          return const TraktDevicePollResult.failure(
            TraktDevicePollStatus.error,
            '设备授权响应缺少 token',
          );
        }
        await store.writeTokens(tokens);
        await store.clearDeviceCode();
        return TraktDevicePollResult.success(tokens);
      case 400:
        return const TraktDevicePollResult.pending();
      case 404:
        await store.clearDeviceCode();
        return const TraktDevicePollResult.failure(
          TraktDevicePollStatus.invalid,
          '设备码无效',
        );
      case 409:
        await store.clearDeviceCode();
        return const TraktDevicePollResult.failure(
          TraktDevicePollStatus.used,
          '设备码已被使用',
        );
      case 410:
        await store.clearDeviceCode();
        return const TraktDevicePollResult.failure(
          TraktDevicePollStatus.expired,
          '设备码已过期',
        );
      case 418:
        await store.clearDeviceCode();
        return const TraktDevicePollResult.failure(
          TraktDevicePollStatus.denied,
          '用户拒绝授权',
        );
      case 429:
        return const TraktDevicePollResult.slowDown();
      default:
        return TraktDevicePollResult.failure(
          TraktDevicePollStatus.error,
          _errorMessage(data) ?? '设备授权失败',
        );
    }
  }

  Future<TraktTokens> refresh(TraktTokens tokens) {
    return _refreshFuture ??= _doRefresh(tokens).whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<TraktTokens> _doRefresh(TraktTokens tokens) async {
    if (tokens.refreshToken.isEmpty) {
      throw const TraktAuthException('missing_refresh_token', '登录已失效');
    }
    final next = await _postToken(
      {
        'refresh_token': tokens.refreshToken,
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'grant_type': 'refresh_token',
      },
      fallbackMessage: '刷新登录失败',
    );
    await store.writeTokens(next);
    return next;
  }

  Future<TraktTokens> ensureValid(TraktTokens tokens) async {
    if (tokens.isExpiringWithin(const Duration(minutes: 5), now: _now())) {
      return refresh(tokens);
    }
    return tokens;
  }

  Future<TraktAccount> getAccount(TraktTokens tokens) async {
    final response = await _get('/users/me', tokens);
    final data = _mapBody(response);
    if (response.statusCode == 200) return TraktAccount.fromJson(data);
    throw TraktAuthException(
      'account_failed',
      _errorMessage(data) ?? '获取 Trakt 账号失败',
    );
  }

  Future<void> revoke(TraktTokens tokens) async {
    for (final url in config.revokeUrls) {
      try {
        final response = await _post(
          url,
          {'token': tokens.accessToken, 'client_id': config.clientId},
        );
        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> clearAuthState() => store.clearAuthState();

  Future<TraktTokens> _postToken(
    Map<String, dynamic> body, {
    required String fallbackMessage,
  }) async {
    TraktAuthException? lastError;
    for (final url in config.tokenUrls) {
      final response = await _post(url, body);
      final data = _mapBody(response);
      if (response.statusCode == 200) {
        final tokens = TraktTokens.fromResponse(data, now: _now());
        if (tokens.accessToken.isEmpty) {
          throw TraktAuthException(
            'invalid_token_response',
            'Trakt 未返回 access token',
          );
        }
        return tokens;
      }
      final message = _errorMessage(data) ?? fallbackMessage;
      lastError = TraktAuthException(
        'token_exchange_failed',
        message,
      );
      if (response.statusCode != 404 && response.statusCode != 405) {
        throw lastError;
      }
    }
    throw lastError ??
        TraktAuthException('token_exchange_failed', fallbackMessage);
  }

  Future<Response<dynamic>> _post(String url, Map<String, dynamic> body) async {
    try {
      return await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(headers: _publicHeaders),
      );
    } on DioException catch (e) {
      if (e.response != null) return e.response!;
      throw TraktAuthException('network_error', e.message ?? '网络请求失败');
    }
  }

  Future<Response<dynamic>> _get(String path, TraktTokens tokens) async {
    try {
      return await _dio.get<dynamic>(
        '${config.apiBase}$path',
        options: Options(headers: headersFor(tokens)),
      );
    } on DioException catch (e) {
      if (e.response != null) return e.response!;
      throw TraktAuthException('network_error', e.message ?? '网络请求失败');
    }
  }

  Map<String, dynamic> _mapBody(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  String? _errorMessage(Map<String, dynamic> data) {
    final message =
        data['error_description'] ?? data['error'] ?? data['message'];
    return message is String && message.isNotEmpty ? message : null;
  }
}
