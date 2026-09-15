import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

const _storageKey = 'himi_app_settings';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  throw UnimplementedError();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  final _storage = const FlutterSecureStorage();

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> update({String? decodeMode, int? bufferSizeMB, bool? showSyncDebug, bool? dvHwDecode, bool? gpuNext}) async {
    state = state.copyWith(
      decodeMode: decodeMode,
      bufferSizeMB: bufferSizeMB,
      showSyncDebug: showSyncDebug,
      dvHwDecode: dvHwDecode,
      gpuNext: gpuNext,
    );
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }
}
