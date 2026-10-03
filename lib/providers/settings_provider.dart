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

  /// 当前设置快照（bootstrap 在 runApp 前读取注入 fvp 全局选项，
  /// `state` 为 protected 成员，子类内访问合法）。
  AppSettings get snapshot => state;

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
    bool? tvMode,
    String? videoOutput,
    bool? renderCompatMode,
    bool? eglFaultSeen,
    Object? themeColor = AppSettings.unsetValue,
  }) async {
    state = state.copyWith(
      decodeMode: decodeMode,
      showSyncDebug: showSyncDebug,
      stereoDownmix: stereoDownmix,
      audioRenderer: audioRenderer,
      // 手动改动音频后端即标记「用户已设置」，旧默认值迁移不再覆盖
      audioRendererUserSet: audioRenderer != null ? true : null,
      deepDiagnostics: deepDiagnostics,
      glassUi: glassUi,
      tvMode: tvMode,
      // 手动改动 TV 开关即标记「用户已设置」，此后自动识别不再覆盖
      tvModeUserSet: tvMode != null ? true : null,
      videoOutput: videoOutput,
      renderCompatMode: renderCompatMode,
      eglFaultSeen: eglFaultSeen,
      themeColor: themeColor,
    );
    await persist();
  }

  /// TV 自动识别（策略 A）：仅当检测为 TV 设备、用户从未手动设置过
  /// 且当前未开启时，静默开启 TV 模式并落盘；其余情况无任何副作用。
  Future<void> applyTvAutoDetection({required bool isTelevision}) async {
    if (!isTelevision || state.tvModeUserSet || state.tvMode) return;
    state = state.copyWith(tvMode: true);
    await persist();
  }

  /// 落盘当前设置（测试中可覆写以绕过平台通道）。
  Future<void> persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }
}
