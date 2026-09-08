import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';

const _storageKey = 'himi_agora_config';

final agoraConfigProvider =
    StateNotifierProvider<AgoraConfigNotifier, AgoraConfigModel?>(
  (ref) => AgoraConfigNotifier(),
);

class AgoraConfigNotifier extends StateNotifier<AgoraConfigModel?> {
  AgoraConfigNotifier() : super(null);

  final _storage = const FlutterSecureStorage();

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      try {
        state = AgoraConfigModel.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> save(AgoraConfigModel config) async {
    state = config;
    await _storage.write(key: _storageKey, value: jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    state = null;
    await _storage.delete(key: _storageKey);
  }
}
