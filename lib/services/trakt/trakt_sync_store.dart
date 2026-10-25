import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';

class TraktSyncStore {
  static const stateKey = 'himi_trakt_sync_state';

  final FlutterSecureStorage _storage;

  TraktSyncStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<TraktSyncState> read() async {
    final raw = await _storage.read(key: stateKey);
    if (raw == null || raw.isEmpty) return const TraktSyncState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TraktSyncState.fromJson(decoded);
      }
      if (decoded is Map) {
        return TraktSyncState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const TraktSyncState();
  }

  Future<void> write(TraktSyncState state) async {
    await _storage.write(key: stateKey, value: jsonEncode(state.toJson()));
  }

  Future<TraktSyncState> recordSuccess(TraktSyncStatistics stats) async {
    final current = await read();
    final next = current.copyWith(
      lastSuccessAt: DateTime.now().toUtc(),
      movies: stats.movies,
      shows: stats.shows,
      episodes: stats.episodes,
    );
    await write(next);
    return next;
  }

  Future<void> clear() => _storage.delete(key: stateKey);
}
