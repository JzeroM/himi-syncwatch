import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_item_reset_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_store.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

final traktTokenStoreProvider = Provider<TraktTokenStore>((ref) {
  return TraktTokenStore();
});

final traktAuthServiceProvider = Provider<TraktAuthService>((ref) {
  return TraktAuthService(store: ref.watch(traktTokenStoreProvider));
});

final traktClientProvider = Provider<TraktClient>((ref) {
  return TraktClient(auth: ref.watch(traktAuthServiceProvider));
});

final traktProvider =
    StateNotifierProvider<TraktProvider, TraktAppState>((ref) {
  return TraktProvider(ref);
});

class TraktAppState {
  final bool initialized;
  final bool connecting;
  final bool syncing;
  final bool configured;
  final TraktTokens? tokens;
  final TraktAccount? account;
  final TraktDeviceCode? deviceCode;
  final TraktSyncState syncState;
  final TraktSyncProgress? liveSync;
  final String? error;

  const TraktAppState({
    this.initialized = false,
    this.connecting = false,
    this.syncing = false,
    this.configured = true,
    this.tokens,
    this.account,
    this.deviceCode,
    this.syncState = const TraktSyncState(),
    this.liveSync,
    this.error,
  });

  bool get connected => tokens != null;

  TraktAppState copyWith({
    bool? initialized,
    bool? connecting,
    bool? syncing,
    bool? configured,
    TraktTokens? tokens,
    TraktAccount? account,
    TraktDeviceCode? deviceCode,
    TraktSyncState? syncState,
    TraktSyncProgress? liveSync,
    String? error,
    bool clearTokens = false,
    bool clearAccount = false,
    bool clearDeviceCode = false,
    bool clearLiveSync = false,
    bool clearError = false,
  }) {
    return TraktAppState(
      initialized: initialized ?? this.initialized,
      connecting: connecting ?? this.connecting,
      syncing: syncing ?? this.syncing,
      configured: configured ?? this.configured,
      tokens: clearTokens ? null : (tokens ?? this.tokens),
      account: clearAccount ? null : (account ?? this.account),
      deviceCode: clearDeviceCode ? null : (deviceCode ?? this.deviceCode),
      syncState: syncState ?? this.syncState,
      liveSync: clearLiveSync ? null : (liveSync ?? this.liveSync),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TraktProvider extends StateNotifier<TraktAppState> {
  final Ref _ref;
  final TraktAuthService _auth;
  final TraktClient _client;
  final TraktSyncStore _syncStore;
  final TraktSyncService _syncService;
  final TraktItemResetService _itemResetService;

  Future<void>? _initFuture;
  Future<void>? _itemResetChain;
  bool _started = false;
  bool _devicePolling = false;

  TraktProvider(this._ref)
      : _auth = _ref.read(traktAuthServiceProvider),
        _client = _ref.read(traktClientProvider),
        _syncStore = TraktSyncStore(),
        _syncService = TraktSyncService(
          client: _ref.read(traktClientProvider),
          store: TraktSyncStore(),
        ),
        _itemResetService = TraktItemResetService(
          client: _ref.read(traktClientProvider),
        ),
        super(TraktAppState(
          configured: _ref.read(traktAuthServiceProvider).config.isConfigured,
        ));

  Future<void> init() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    if (_started) return;
    _started = true;
    TraktTokens? stored;
    TraktSyncState syncState;
    try {
      stored = await _auth.store.readTokens();
      syncState = await _syncStore.read();
    } catch (e) {
      if (mounted) {
        state = state.copyWith(initialized: true, error: e.toString());
      }
      return;
    }
    if (stored == null) {
      if (mounted) {
        state = state.copyWith(initialized: true, syncState: syncState);
      }
      return;
    }
    _client.tokens = stored;
    if (mounted) {
      state = state.copyWith(
        initialized: true,
        tokens: stored,
        syncState: syncState,
      );
    }
    try {
      final valid = await _auth.ensureValid(stored);
      _client.tokens = valid;
      final account = await _auth.getAccount(valid);
      if (mounted) {
        state = state.copyWith(tokens: valid, account: account);
      }
    } on TraktAuthException catch (e) {
      if (e.code == 'network_error') {
        if (mounted) state = state.copyWith(error: e.message);
        return;
      }
      await _auth.clearAuthState();
      _client.tokens = null;
      if (mounted) {
        state = state.copyWith(
          clearTokens: true,
          clearAccount: true,
          error: e.message,
        );
      }
    } catch (_) {}
  }

  Future<Uri?> beginPkce() async {
    if (!state.configured) {
      state = state.copyWith(error: '当前构建未注入 Trakt Client ID');
      return null;
    }
    state = state.copyWith(connecting: true, clearError: true);
    try {
      final uri = await _auth.beginPkce();
      if (mounted) state = state.copyWith(connecting: false);
      return uri;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(connecting: false, error: e.toString());
      }
      return null;
    }
  }

  bool isTraktCallback(Uri uri) {
    return uri.scheme == 'himi' && uri.host == 'oauth' && uri.path == '/trakt';
  }

  Future<bool> handleCallback(Uri uri) async {
    if (!isTraktCallback(uri)) return false;
    state = state.copyWith(connecting: true, clearError: true);
    try {
      final tokens = await _auth.handleCallback(uri);
      _client.tokens = tokens;
      TraktAccount? account;
      try {
        account = await _auth.getAccount(tokens);
      } catch (_) {}
      if (mounted) {
        state = state.copyWith(
          connecting: false,
          tokens: tokens,
          account: account,
          clearDeviceCode: true,
        );
      }
      unawaited(syncNow());
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          connecting: false,
          error: e is TraktAuthException ? e.message : e.toString(),
        );
      }
      return false;
    }
  }

  Future<TraktDeviceCode?> startDeviceFlow() async {
    if (!state.configured) {
      state = state.copyWith(error: '当前构建未注入 Trakt Client ID');
      return null;
    }
    state = state.copyWith(connecting: true, clearError: true);
    try {
      final code = await _auth.startDeviceFlow();
      if (mounted) {
        state = state.copyWith(connecting: false, deviceCode: code);
      }
      return code;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          connecting: false,
          error: e is TraktAuthException ? e.message : e.toString(),
        );
      }
      return null;
    }
  }

  Future<void> pollDeviceFlow() async {
    final code = state.deviceCode;
    if (code == null || state.connecting || _devicePolling) return;
    _devicePolling = true;
    try {
      final result = await _auth.pollDeviceFlow(code);
      if (result.status == TraktDevicePollStatus.success) {
        final tokens = result.tokens!;
        _client.tokens = tokens;
        TraktAccount? account;
        try {
          account = await _auth.getAccount(tokens);
        } catch (_) {}
        if (mounted) {
          state = state.copyWith(
            tokens: tokens,
            account: account,
            clearDeviceCode: true,
          );
        }
        unawaited(syncNow());
      } else if (result.status == TraktDevicePollStatus.slowDown) {
      } else if (result.status != TraktDevicePollStatus.pending) {
        if (mounted) {
          state = state.copyWith(
            clearDeviceCode: true,
            error: result.message ?? '设备授权失败',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
    } finally {
      _devicePolling = false;
    }
  }

  Future<void> cancelDeviceFlow() async {
    await _auth.store.clearDeviceCode();
    if (mounted) state = state.copyWith(clearDeviceCode: true);
  }

  Future<void> disconnect() async {
    final tokens = _client.tokens ?? state.tokens;
    if (tokens != null) {
      await _auth.revoke(tokens);
    }
    await _auth.clearAuthState();
    _client.tokens = null;
    if (mounted) {
      state = state.copyWith(
        clearTokens: true,
        clearAccount: true,
        clearDeviceCode: true,
      );
    }
  }

  Future<void> maybeAutoSync() async {
    if (!state.initialized || !state.connected || state.syncing) return;
    if (!_ref.read(settingsProvider).traktAutoSync) return;
    final last = state.syncState.lastSuccessAt;
    if (last != null) {
      final elapsed = DateTime.now().toUtc().difference(last);
      if (elapsed < _ref.read(settingsProvider).traktSyncInterval) return;
    }
    await syncNow();
  }

  Future<void> syncNow() async {
    if (state.syncing || !state.connected) return;
    final pendingReset = _itemResetChain;
    if (pendingReset != null) await pendingReset;
    final servers = _buildServers();
    if (servers.isEmpty) return;
    state = state.copyWith(
      syncing: true,
      liveSync: TraktSyncProgress(
        phase: TraktSyncPhase.readingRemote,
        serversTotal: servers.length,
      ),
    );
    try {
      final result = await _syncService.sync(
        servers,
        onProgress: (progress) {
          if (mounted) state = state.copyWith(liveSync: progress);
        },
      );
      if (mounted) {
        state = state.copyWith(
          syncing: false,
          syncState: result.state,
          clearLiveSync: true,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(syncing: false, clearLiveSync: true);
      }
    }
  }

  Future<void> resetItemProgress({
    required String serverConfigId,
    required String itemId,
    required bool removeWatched,
  }) {
    if (!state.connected) return Future<void>.value();
    final origin = _serverConfig(serverConfigId);
    if (origin == null) return Future<void>.value();
    final servers = _buildServers();
    if (servers.isEmpty) return Future<void>.value();
    final previous = _itemResetChain ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        await _itemResetService.resetItem(
          servers: servers,
          serverConfigId: origin.id,
          itemId: itemId,
          removeWatched: removeWatched,
        );
      } catch (_) {}
    });
    _itemResetChain = next;
    return next;
  }

  Future<void> reportPlaybackProgress({
    required String serverConfigId,
    required String itemId,
    required int positionMs,
  }) async {
    if (!state.connected) return;
    final config = _serverConfig(serverConfigId);
    if (config == null) return;
    try {
      final service = _ref.read(embyServiceFactoryProvider)(config);
      final item = await service.getItemDetails(itemId);
      if (item == null) return;
      if (item.isWatched) {
        await _writeHistoryForItem(service, item, watched: true);
        return;
      }
      if (positionMs <= 0) return;
      final percent = _progressPercent(item, positionMs);
      if (item.isMovie) {
        final ids = _idsFromMedia(item);
        if (!_hasIds(ids)) return;
        await _client.pauseMovie(ids: ids, progress: percent);
      } else if (item.isEpisode) {
        final season = item.parentIndexNumber;
        final episode = item.indexNumber;
        if (season == null || episode == null) return;
        final showIds = await _showIdsFor(service, item);
        final ids = _idsFromMedia(item);
        if (!_hasIds(ids) && !_hasIds(showIds)) return;
        await _client.pauseEpisode(
          ids: ids,
          showIds: showIds,
          season: season,
          episode: episode,
          progress: percent,
        );
      }
    } catch (_) {}
  }

  Future<void> reportWatched({
    required String serverConfigId,
    required String itemId,
  }) async {
    await _reportItemHistory(
      serverConfigId: serverConfigId,
      itemId: itemId,
      watched: true,
    );
  }

  Future<void> _reportItemHistory({
    required String serverConfigId,
    required String itemId,
    required bool watched,
  }) async {
    if (!state.connected) return;
    final config = _serverConfig(serverConfigId);
    if (config == null) return;
    try {
      final service = _ref.read(embyServiceFactoryProvider)(config);
      final item = await service.getItemDetails(itemId);
      if (item == null) return;
      await _writeHistoryForItem(service, item, watched: watched);
    } catch (_) {}
  }

  Future<void> reportSeriesHistory({
    required String serverConfigId,
    required MediaItem series,
    required List<MediaItem> episodes,
    required bool watched,
  }) async {
    if (!state.connected) return;
    if (_serverConfig(serverConfigId) == null) return;
    final showIds = _idsFromMedia(series);
    if (!_hasIds(showIds)) return;
    final seasons = <int, Set<int>>{};
    for (final episode in episodes) {
      final season = episode.parentIndexNumber;
      final number = episode.indexNumber;
      if (season == null || number == null) continue;
      seasons.putIfAbsent(season, () => <int>{}).add(number);
    }
    if (seasons.isEmpty) return;
    final shows = [
      {
        'ids': showIds.toJson(),
        'seasons': seasons.entries
            .map((entry) => {
                  'number': entry.key,
                  'episodes':
                      entry.value.map((number) => {'number': number}).toList(),
                })
            .toList(),
      },
    ];
    try {
      if (watched) {
        await _client.addHistory(shows: shows);
      } else {
        await _client.removeHistory(shows: shows);
      }
    } catch (_) {}
  }

  Future<void> _writeHistoryForItem(
    EmbyService service,
    MediaItem item, {
    required bool watched,
  }) async {
    if (item.isMovie) {
      final ids = _idsFromMedia(item);
      if (!_hasIds(ids)) return;
      final movies = [
        {'ids': ids.toJson()},
      ];
      if (watched) {
        await _client.addHistory(movies: movies);
      } else {
        await _client.removeHistory(movies: movies);
      }
      return;
    }
    if (!item.isEpisode) return;
    final season = item.parentIndexNumber;
    final episode = item.indexNumber;
    if (season == null || episode == null) return;
    final showIds = await _showIdsFor(service, item);
    if (!_hasIds(showIds)) return;
    final shows = [
      {
        'ids': showIds.toJson(),
        'seasons': [
          {
            'number': season,
            'episodes': [
              {'number': episode},
            ],
          },
        ],
      },
    ];
    if (watched) {
      await _client.addHistory(shows: shows);
    } else {
      await _client.removeHistory(shows: shows);
    }
  }

  Future<TraktMediaIds> _showIdsFor(
    EmbyService service,
    MediaItem episode,
  ) async {
    final seriesId = episode.seriesId;
    if (seriesId == null) return const TraktMediaIds();
    final series = await service.getItemDetails(seriesId);
    return series == null ? const TraktMediaIds() : _idsFromMedia(series);
  }

  double _progressPercent(MediaItem item, int positionMs) {
    final runtime = item.runTimeTicks ?? 0;
    if (runtime <= 0) return 0.1;
    final percent = positionMs / (runtime / 10000) * 100;
    return percent.clamp(0.1, 95.0).toDouble();
  }

  TraktMediaIds _idsFromMedia(MediaItem item) {
    return TraktMediaIds(
      tmdb: int.tryParse(item.providerId('tmdb') ?? ''),
      tvdb: int.tryParse(item.providerId('tvdb') ?? ''),
      imdb: item.providerId('imdb'),
    );
  }

  bool _hasIds(TraktMediaIds ids) =>
      (ids.trakt != null && ids.trakt! > 0) ||
      (ids.tmdb != null && ids.tmdb! > 0) ||
      (ids.tvdb != null && ids.tvdb! > 0) ||
      (ids.imdb != null && ids.imdb!.trim().isNotEmpty);

  EmbyServerConfig? _serverConfig(String id) {
    final settings = _ref.read(settingsProvider);
    final current = _ref.read(embyConfigProvider);
    if (current != null && (id.isEmpty || current.id == id)) {
      return settings.isTraktServerEnabled(current.id) ? current : null;
    }
    for (final server in _ref.read(embyServerListProvider)) {
      if (server.id == id) {
        return settings.isTraktServerEnabled(server.id) ? server : null;
      }
    }
    return null;
  }

  List<TraktServerHandle> _buildServers() {
    final settings = _ref.read(settingsProvider);
    final configs = <String, EmbyServerConfig>{};
    final current = _ref.read(embyConfigProvider);
    if (current != null) configs[current.id] = current;
    for (final server in _ref.read(embyServerListProvider)) {
      configs[server.id] = server;
    }
    final factory = _ref.read(embyServiceFactoryProvider);
    final handles = <TraktServerHandle>[];
    for (final config in configs.values) {
      if (!config.isAuthenticated) continue;
      if (!settings.isTraktServerEnabled(config.id)) continue;
      handles.add(TraktServerHandle(
        configId: config.id,
        service: factory(config),
      ));
    }
    return handles;
  }
}
