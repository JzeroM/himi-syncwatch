import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

enum TraktItemKind { movie, episode }

class TraktSyncEntry {
  final TraktItemKind kind;
  final TraktMediaIds ids;
  final TraktMediaIds showIds;
  final int? season;
  final int? episode;
  final bool watched;
  final int positionMs;
  final double? progressPercent;
  final int? runtimeMs;
  final DateTime? lastPlayed;
  final String? serverConfigId;
  final String? itemId;
  final int? playbackId;

  const TraktSyncEntry({
    required this.kind,
    this.ids = const TraktMediaIds(),
    this.showIds = const TraktMediaIds(),
    this.season,
    this.episode,
    this.watched = false,
    this.positionMs = 0,
    this.progressPercent,
    this.runtimeMs,
    this.lastPlayed,
    this.serverConfigId,
    this.itemId,
    this.playbackId,
  });

  bool get isMovie => kind == TraktItemKind.movie;

  bool get isEpisode => kind == TraktItemKind.episode;

  bool get hasLocal => serverConfigId != null && itemId != null;

  List<String> get identityTokens {
    final tokens = <String>[];
    void add(String prefix, Object? value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != '0') tokens.add('$prefix:$text');
    }

    add('trakt', ids.trakt);
    add('tmdb', ids.tmdb);
    add('tvdb', ids.tvdb);
    add('imdb', ids.imdb);
    if (isEpisode) {
      add('show-trakt', showIds.trakt);
      add('show-tmdb', showIds.tmdb);
      add('show-tvdb', showIds.tvdb);
      add('show-imdb', showIds.imdb);
    }
    if (tokens.isEmpty) {
      if (hasLocal) return ['local:$serverConfigId:$itemId'];
      if (playbackId != null) return ['playback:$playbackId'];
    }
    return tokens;
  }

  String get showIdentity {
    final tokens = <String>[];
    void add(String prefix, Object? value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != '0') tokens.add('$prefix:$text');
    }

    add('trakt', showIds.trakt);
    add('tmdb', showIds.tmdb);
    add('tvdb', showIds.tvdb);
    add('imdb', showIds.imdb);
    tokens.sort();
    return tokens.isEmpty ? 'show:unknown' : tokens.join('|');
  }
}

class TraktSyncState {
  final DateTime? lastSuccessAt;
  final int movies;
  final int shows;
  final int episodes;
  final Map<String, DateTime> resetAt;

  const TraktSyncState({
    this.lastSuccessAt,
    this.movies = 0,
    this.shows = 0,
    this.episodes = 0,
    this.resetAt = const {},
  });

  Map<String, dynamic> toJson() => {
        if (lastSuccessAt != null)
          'last_success_at': lastSuccessAt!.toIso8601String(),
        'movies': movies,
        'shows': shows,
        'episodes': episodes,
        'reset_at': resetAt.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  factory TraktSyncState.fromJson(Map<String, dynamic> json) {
    final rawReset = json['reset_at'];
    final reset = <String, DateTime>{};
    if (rawReset is Map) {
      rawReset.forEach((key, value) {
        final parsed = DateTime.tryParse(value?.toString() ?? '');
        if (parsed != null) reset[key.toString()] = parsed;
      });
    }
    return TraktSyncState(
      lastSuccessAt:
          DateTime.tryParse(json['last_success_at']?.toString() ?? ''),
      movies: (json['movies'] as num?)?.toInt() ?? 0,
      shows: (json['shows'] as num?)?.toInt() ?? 0,
      episodes: (json['episodes'] as num?)?.toInt() ?? 0,
      resetAt: reset,
    );
  }

  TraktSyncState copyWith({
    DateTime? lastSuccessAt,
    int? movies,
    int? shows,
    int? episodes,
    Map<String, DateTime>? resetAt,
  }) {
    return TraktSyncState(
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      movies: movies ?? this.movies,
      shows: shows ?? this.shows,
      episodes: episodes ?? this.episodes,
      resetAt: resetAt ?? this.resetAt,
    );
  }
}

class TraktSyncStatistics {
  final int movies;
  final int shows;
  final int episodes;

  const TraktSyncStatistics({
    this.movies = 0,
    this.shows = 0,
    this.episodes = 0,
  });
}

enum TraktActionType {
  markEmbyWatched,
  unmarkEmbyWatched,
  clearEmbyProgress,
  writeEmbyProgress,
  addTraktHistory,
  deleteTraktPlayback,
  pauseTrakt,
}

class TraktSyncAction {
  final TraktActionType type;
  final TraktSyncEntry? entry;
  final String? serverConfigId;
  final String? itemId;
  final int? positionMs;
  final double? progressPercent;
  final int? playbackId;

  const TraktSyncAction({
    required this.type,
    this.entry,
    this.serverConfigId,
    this.itemId,
    this.positionMs,
    this.progressPercent,
    this.playbackId,
  });
}

class TraktSyncPlan {
  final List<TraktSyncAction> actions;
  final TraktSyncStatistics stats;

  const TraktSyncPlan({required this.actions, required this.stats});
}

class TraktSyncResult {
  final TraktSyncState state;
  final TraktSyncStatistics stats;
  final int serversProcessed;

  const TraktSyncResult({
    required this.state,
    required this.stats,
    required this.serversProcessed,
  });
}

class TraktServerHandle {
  final String configId;
  final EmbyService service;

  const TraktServerHandle({required this.configId, required this.service});
}
