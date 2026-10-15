import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/tv_device.dart';

/// 手机端已配对 TV 持久化（secure storage 单键 JSON）。
class PairedTvStore {
  PairedTvStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'himi_paired_tv';

  final FlutterSecureStorage _storage;

  Future<PairedTv?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final tv = PairedTv.fromJson(decoded);
      return tv.deviceId.isEmpty || tv.token.isEmpty ? null : tv;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PairedTv tv) async {
    await _storage.write(key: _key, value: jsonEncode(tv.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
