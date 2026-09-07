import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

final embyConfigProvider =
    StateNotifierProvider<EmbyConfigNotifier, EmbyServerConfig?>(
  (ref) => EmbyConfigNotifier(),
);

final embyServerListProvider =
    StateNotifierProvider<EmbyServerListNotifier, List<EmbyServerConfig>>(
  (ref) => EmbyServerListNotifier(),
);

class EmbyConfigNotifier extends StateNotifier<EmbyServerConfig?> {
  EmbyConfigNotifier() : super(null) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('emby_config');
    if (configJson != null) {
      final map = jsonDecode(configJson) as Map<String, dynamic>;
      if (!map.containsKey('id')) {
        map['id'] = 'server_0';
      }
      state = EmbyServerConfig.fromJson(map);
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

class EmbyServerListNotifier extends StateNotifier<List<EmbyServerConfig>> {
  EmbyServerListNotifier() : super([]) {
    _loadList();
  }

  Future<void> _loadList() async {
    final prefs = await SharedPreferences.getInstance();
    final listJson = prefs.getString('emby_server_list');
    if (listJson != null) {
      final list = jsonDecode(listJson) as List<dynamic>;
      state = list.map((e) => EmbyServerConfig.fromJson(e)).toList();
    }
  }

  Future<void> addServer(EmbyServerConfig config) async {
    state = [...state, config];
    await _saveList();
  }

  Future<void> removeServer(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _saveList();
  }

  Future<void> updateServer(EmbyServerConfig config) async {
    state = state.map((s) => s.id == config.id ? config : s).toList();
    await _saveList();
  }

  Future<void> _saveList() async {
    final prefs = await SharedPreferences.getInstance();
    final listJson = jsonEncode(state.map((s) => s.toJson()).toList());
    await prefs.setString('emby_server_list', listJson);
  }
}

final embyServiceProvider = Provider<EmbyService>((ref) {
  final service = EmbyService();
  final config = ref.watch(embyConfigProvider);

  if (config != null && config.isAuthenticated) {
    service.configure(
      serverUrl: config.serverUrl,
      accessToken: config.accessToken!,
      userId: config.userId,
    );
  }

  return service;
});
