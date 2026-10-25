import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';

class TraktTokenStore {
  static const tokensKey = 'himi_trakt_tokens';
  static const pkceKey = 'himi_trakt_pkce';
  static const deviceKey = 'himi_trakt_device';

  final FlutterSecureStorage _storage;

  TraktTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<TraktTokens?> readTokens() async {
    final raw = await _storage.read(key: tokensKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return TraktTokens.fromJson(json);
    } catch (_) {}
    return null;
  }

  Future<void> writeTokens(TraktTokens tokens) async {
    await _storage.write(key: tokensKey, value: jsonEncode(tokens.toJson()));
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: tokensKey);
  }

  Future<TraktPkceSession?> readPkce() async {
    final raw = await _storage.read(key: pkceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return TraktPkceSession.fromJson(json);
    } catch (_) {}
    return null;
  }

  Future<void> writePkce(TraktPkceSession session) async {
    await _storage.write(key: pkceKey, value: jsonEncode(session.toJson()));
  }

  Future<void> clearPkce() async {
    await _storage.delete(key: pkceKey);
  }

  Future<TraktDeviceCode?> readDeviceCode() async {
    final raw = await _storage.read(key: deviceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return TraktDeviceCode.fromJson(json);
      }
    } catch (_) {}
    return null;
  }

  Future<void> writeDeviceCode(TraktDeviceCode code) async {
    await _storage.write(
      key: deviceKey,
      value: jsonEncode({
        'device_code': code.deviceCode,
        'user_code': code.userCode,
        'verification_url': code.verificationUrl,
        'expires_in': code.expiresIn,
        'interval': code.interval,
      }),
    );
  }

  Future<void> clearDeviceCode() async {
    await _storage.delete(key: deviceKey);
  }

  Future<void> clearAuthState() async {
    await Future.wait([
      clearTokens(),
      clearPkce(),
      clearDeviceCode(),
    ]);
  }
}
