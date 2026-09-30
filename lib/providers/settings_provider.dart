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

  Future<void> update({
    String? decodeMode,
    bool? showSyncDebug,
    bool? stereoDownmix,
    String? audioRenderer,
    bool? deepDiagnostics,
    bool? glassUi,
    Object? themeColor = AppSettings.unsetValue,
  }) async {
    state = state.copyWith(
      decodeMode: decodeMode,
      showSyncDebug: showSyncDebug,
      stereoDownmix: stereoDownmix,
      audioRenderer: audioRenderer,
      deepDiagnostics: deepDiagnostics,
      glassUi: glassUi,
      themeColor: themeColor,
    );
    await persist();
  }

  /// 落盘当前设置（测试中可覆写以绕过平台通道）。
  Future<void> persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }
}
