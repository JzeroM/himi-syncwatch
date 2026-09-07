import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

final embyConfigProvider =
    StateNotifierProvider<EmbyConfigNotifier, EmbyServerConfig?>(
  (ref) => EmbyConfigNotifier(),
);

class EmbyConfigNotifier extends StateNotifier<EmbyServerConfig?> {
  EmbyConfigNotifier() : super(null) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('emby_config');
    if (configJson != null) {
      state = EmbyServerConfig.fromJson(jsonDecode(configJson));
    }
  }

  Future<void> saveConfig(EmbyServerConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emby_config', jsonEncode(config.toJson()));
  }

  Future<void> clearConfig() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('emby_config');
  }
}

final embyServiceProvider = Provider<EmbyService>((ref) {
  final service = EmbyService();
  final config = ref.watch(embyConfigProvider);

  if (config != null && config.isAuthenticated) {
    service.configure(
      serverUrl: config.serverUrl,
      accessToken: config.accessToken!,
    );
  }

  return service;
});
